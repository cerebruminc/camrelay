import CamRelayCore
import CoreImage
import Foundation

struct PlaybackFrame: Sendable {
    let media: MediaFrame
    let generation: UInt64
}

struct PlaybackSnapshot: Sendable {
    let selected: String
    let paused: Bool
    let generation: UInt64
    let positionNanoseconds: UInt64
    let error: String?
}

/// Owns a prepared decoder until it is transferred to the playback engine.
final class PreparedFixture: @unchecked Sendable {
    let name: String
    let source: any FrameSource
    let firstFrame: MediaFrame

    init(name: String, source: any FrameSource) throws {
        self.name = name
        self.source = source
        firstFrame = try source.nextFrame()
        guard firstFrame.data.count == source.format.frameByteCount,
              firstFrame.durationNanoseconds > 0 else {
            throw RelayError("Fixture \(name) has an invalid first frame.")
        }
    }
}

/// Decoder access and playback mutations share a lock; socket writes never hold it.
final class PlaybackEngine: @unchecked Sendable {
    let format: FrameFormat
    private let lock = NSLock()
    private let converter: FrameConverter
    private var prepared: PreparedFixture
    private var clock: PlaybackClock
    private var current: MediaFrame
    private var lookahead: MediaFrame?
    private var rendered: Data
    private var failure: String?

    init(initial: PreparedFixture, outputFormat: FrameFormat? = nil, paused: Bool = false) throws {
        let initialFormat = initial.source.format
        guard isSupportedRelayOutput(initialFormat) else {
            throw RelayError("The initial fixture must have dimensions up to 4096 pixels and a supported frame rate.")
        }
        format = outputFormat ?? initialFormat
        guard isSupportedRelayOutput(format) else {
            throw RelayError("The relay output must have dimensions up to 4096 pixels and a supported frame rate.")
        }
        let converter = FrameConverter()
        self.converter = converter
        prepared = initial
        clock = PlaybackClock(paused: paused)
        current = initial.firstFrame
        rendered = try converter.convert(initial.firstFrame, from: initialFormat, to: format)
    }

    @discardableResult
    func select(_ replacement: PreparedFixture, at time: UInt64, paused: Bool) throws -> UInt64 {
        // Prepare pixels before changing the active decoder. Failure keeps the old feed intact.
        let pixels = try converter.convert(replacement.firstFrame, from: replacement.source.format, to: format)
        return lock.withLock {
            prepared = replacement
            current = replacement.firstFrame
            lookahead = nil
            rendered = pixels
            failure = nil
            clock.select(at: time, paused: paused)
            return clock.generation
        }
    }

    @discardableResult
    func setPaused(_ paused: Bool, at time: UInt64) -> UInt64 {
        lock.withLock {
            clock.setPaused(paused, at: time)
            return clock.generation
        }
    }

    func snapshot(at time: UInt64) -> PlaybackSnapshot {
        lock.withLock {
            PlaybackSnapshot(
                selected: prepared.name, paused: clock.paused, generation: clock.generation,
                positionNanoseconds: clock.position(at: time), error: failure
            )
        }
    }

    func frame(at time: UInt64, duration: UInt64) -> PlaybackFrame {
        lock.withLock {
            let sourceTime = clock.position(at: time)
            if failure == nil {
                do {
                    var changed = false
                    while true {
                        if lookahead == nil {
                            let next = try prepared.source.nextFrame()
                            guard next.presentationTimeNanoseconds > current.presentationTimeNanoseconds,
                                  next.durationNanoseconds > 0,
                                  next.data.count == prepared.source.format.frameByteCount else {
                                throw RelayError("Fixture \(prepared.name) returned an invalid frame or timestamp.")
                            }
                            lookahead = next
                        }
                        guard let next = lookahead, next.presentationTimeNanoseconds <= sourceTime else { break }
                        current = next
                        lookahead = nil
                        changed = true
                    }
                    if changed {
                        rendered = try converter.convert(current, from: prepared.source.format, to: format)
                    }
                } catch {
                    failure = error.localizedDescription
                    clock.setPaused(true, at: time)
                }
            }
            return PlaybackFrame(
                media: MediaFrame(data: rendered, presentationTimeNanoseconds: time, durationNanoseconds: duration),
                generation: clock.generation
            )
        }
    }
}

func preferredRelayOutputFormat(initial: FrameFormat, candidates: [FrameFormat]) -> FrameFormat {
    candidates.reduce(initial) { selected, candidate in
        guard isSupportedRelayOutput(candidate) else { return selected }
        let selectedPixels = Int64(selected.width) * Int64(selected.height)
        let candidatePixels = Int64(candidate.width) * Int64(candidate.height)
        if candidatePixels > selectedPixels {
            return candidate
        }
        if candidate.width == selected.width,
           candidate.height == selected.height,
           candidate.framesPerSecond > selected.framesPerSecond {
            return candidate
        }
        return selected
    }
}

private func isSupportedRelayOutput(_ format: FrameFormat) -> Bool {
    format.width > 0 && format.height > 0 && format.width <= 4096 && format.height <= 4096
        && format.bytesPerRow == format.width * 4
        && (1...120).contains(format.framesPerSecond)
}

private final class FrameConverter: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    func convert(_ frame: MediaFrame, from source: FrameFormat, to target: FrameFormat) throws -> Data {
        guard frame.data.count == source.frameByteCount else { throw RelayError("Invalid fixture pixel payload.") }
        if source.width == target.width && source.height == target.height && source.bytesPerRow == target.bytesPerRow {
            return frame.data
        }
        guard source.width > 0, source.height > 0 else { throw RelayError("Invalid fixture dimensions.") }
        let scale = min(CGFloat(target.width) / CGFloat(source.width), CGFloat(target.height) / CGFloat(source.height))
        let x = (CGFloat(target.width) - CGFloat(source.width) * scale) / 2
        let y = (CGFloat(target.height) - CGFloat(source.height) * scale) / 2
        let image = CIImage(
            bitmapData: frame.data, bytesPerRow: source.bytesPerRow,
            size: CGSize(width: source.width, height: source.height), format: .BGRA8, colorSpace: colorSpace
        ).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: x, y: y))
        let bounds = CGRect(x: 0, y: 0, width: target.width, height: target.height)
        let composed = image.composited(over: CIImage(color: .black)).cropped(to: bounds)
        var pixels = Data(count: target.frameByteCount)
        pixels.withUnsafeMutableBytes { bytes in
            context.render(
                composed, toBitmap: bytes.baseAddress!, rowBytes: target.bytesPerRow,
                bounds: bounds, format: .BGRA8, colorSpace: colorSpace
            )
        }
        return pixels
    }
}
