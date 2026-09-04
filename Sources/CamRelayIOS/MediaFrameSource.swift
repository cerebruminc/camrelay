import AVFoundation
import CamRelayCore
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO

struct FrameFormat: Equatable, Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let framesPerSecond: Int

    var frameByteCount: Int {
        bytesPerRow * height
    }
}

struct MediaFrame: Sendable {
    let data: Data
    let presentationTimeNanoseconds: UInt64
    let durationNanoseconds: UInt64
}

protocol FrameSource: AnyObject {
    var format: FrameFormat { get }
    func nextFrame() throws -> MediaFrame
    func restart() throws
}

final class MediaFrameSource: FrameSource {
    let format: FrameFormat

    private enum Storage {
        case image(Data)
        case video(VideoFrameReader)
    }

    private let storage: Storage
    private var imageFrameNumber: UInt64 = 0

    init(fixture: MediaFixture) async throws {
        switch fixture.kind {
        case .image:
            let decoded = try Self.decodeImage(at: fixture.url)
            format = decoded.format
            storage = .image(decoded.data)
        case .video:
            let reader = try await VideoFrameReader(url: fixture.url)
            format = reader.format
            storage = .video(reader)
        }
    }

    func nextFrame() throws -> MediaFrame {
        switch storage {
        case .image(let data):
            let framesPerSecond = UInt64(format.framesPerSecond)
            let presentationTime = imageFrameNumber * 1_000_000_000 / framesPerSecond
            imageFrameNumber += 1
            let nextPresentationTime = imageFrameNumber * 1_000_000_000 / framesPerSecond
            return MediaFrame(
                data: data,
                presentationTimeNanoseconds: presentationTime,
                durationNanoseconds: nextPresentationTime - presentationTime
            )
        case .video(let reader):
            return try reader.nextFrame()
        }
    }

    func restart() throws {
        switch storage {
        case .image:
            imageFrameNumber = 0
        case .video(let reader):
            try reader.restart()
        }
    }

    private static func decodeImage(at url: URL) throws -> (format: FrameFormat, data: Data) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MediaFrameSourceError.cannotDecode(url.lastPathComponent)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw MediaFrameSourceError.cannotDecode(url.lastPathComponent)
        }

        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else {
            throw MediaFrameSourceError.cannotDecode(url.lastPathComponent)
        }

        return (
            FrameFormat(width: width, height: height, bytesPerRow: bytesPerRow, framesPerSecond: 30),
            Data(bytes)
        )
    }
}

private final class VideoFrameReader {
    let format: FrameFormat

    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let sourceStartTime: CMTime
    private let loopDurationNanoseconds: UInt64
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var pendingFrame: MediaFrame?
    private var loopOffsetNanoseconds: UInt64 = 0

    init(url: URL) async throws {
        asset = AVURLAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaFrameSourceError.noVideoTrack(url.lastPathComponent)
        }
        track = videoTrack

        let fps = try await videoTrack.load(.nominalFrameRate).rounded(.toNearestOrAwayFromZero)
        let framesPerSecond = max(1, min(60, Int(fps > 0 ? fps : 30)))

        let assetDuration = try await asset.load(.duration)

        var configuredReader: AVAssetReader?
        var configuredOutput: AVAssetReaderTrackOutput?
        try Self.configureReader(
            asset: asset,
            track: track,
            reader: &configuredReader,
            output: &configuredOutput
        )
        reader = configuredReader
        output = configuredOutput
        guard let first = try Self.copyFrame(from: output) else {
            throw MediaFrameSourceError.noVideoFrames(url.lastPathComponent)
        }
        sourceStartTime = first.presentationTime
        let fallbackFrameDuration = UInt64(1_000_000_000 / framesPerSecond)
        loopDurationNanoseconds = Self.nanoseconds(
            for: assetDuration,
            fallback: Self.nanoseconds(for: first.duration, fallback: fallbackFrameDuration)
        )
        pendingFrame = Self.makeFrame(
            from: first,
            sourceStartTime: sourceStartTime,
            loopOffsetNanoseconds: 0,
            fallbackDurationNanoseconds: fallbackFrameDuration
        )
        format = FrameFormat(
            width: first.width,
            height: first.height,
            bytesPerRow: first.width * 4,
            framesPerSecond: framesPerSecond
        )
    }

    func nextFrame() throws -> MediaFrame {
        if let pendingFrame {
            self.pendingFrame = nil
            return pendingFrame
        }

        if let frame = try Self.copyFrame(from: output) {
            return makeFrame(from: frame)
        }

        loopOffsetNanoseconds += loopDurationNanoseconds
        try configureReader()
        guard let frame = try Self.copyFrame(from: output) else {
            throw MediaFrameSourceError.noVideoFrames(asset.url.lastPathComponent)
        }
        return makeFrame(from: frame)
    }

    func restart() throws {
        loopOffsetNanoseconds = 0
        try configureReader()
        pendingFrame = nil
    }

    private func configureReader() throws {
        reader?.cancelReading()
        try Self.configureReader(asset: asset, track: track, reader: &reader, output: &output)
    }

    private func makeFrame(from frame: RawVideoFrame) -> MediaFrame {
        Self.makeFrame(
            from: frame,
            sourceStartTime: sourceStartTime,
            loopOffsetNanoseconds: loopOffsetNanoseconds,
            fallbackDurationNanoseconds: UInt64(1_000_000_000 / format.framesPerSecond)
        )
    }

    private static func configureReader(
        asset: AVURLAsset,
        track: AVAssetTrack,
        reader: inout AVAssetReader?,
        output: inout AVAssetReaderTrackOutput?
    ) throws {
        let newReader = try AVAssetReader(asset: asset)
        let newOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
        newOutput.alwaysCopiesSampleData = false
        guard newReader.canAdd(newOutput) else {
            throw MediaFrameSourceError.readerConfigurationFailed
        }
        newReader.add(newOutput)
        guard newReader.startReading() else {
            throw newReader.error ?? MediaFrameSourceError.readerConfigurationFailed
        }
        reader = newReader
        output = newOutput
    }

    private static func copyFrame(from output: AVAssetReaderTrackOutput?) throws -> RawVideoFrame? {
        guard let sampleBuffer = output?.copyNextSampleBuffer() else {
            return nil
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw MediaFrameSourceError.missingPixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw MediaFrameSourceError.missingPixelBuffer
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let destinationBytesPerRow = width * 4
        var data = Data(count: destinationBytesPerRow * height)
        data.withUnsafeMutableBytes { destination in
            for row in 0..<height {
                let sourceRow = baseAddress.advanced(by: row * sourceBytesPerRow)
                let destinationRow = destination.baseAddress!.advanced(by: row * destinationBytesPerRow)
                destinationRow.copyMemory(from: sourceRow, byteCount: destinationBytesPerRow)
            }
        }
        return RawVideoFrame(
            data: data,
            width: width,
            height: height,
            presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            duration: CMSampleBufferGetDuration(sampleBuffer)
        )
    }

    private static func makeFrame(
        from frame: RawVideoFrame,
        sourceStartTime: CMTime,
        loopOffsetNanoseconds: UInt64,
        fallbackDurationNanoseconds: UInt64
    ) -> MediaFrame {
        let relativePresentationTime = CMTimeSubtract(frame.presentationTime, sourceStartTime)
        return MediaFrame(
            data: frame.data,
            presentationTimeNanoseconds: loopOffsetNanoseconds + nanoseconds(
                for: relativePresentationTime,
                fallback: 0
            ),
            durationNanoseconds: nanoseconds(
                for: frame.duration,
                fallback: fallbackDurationNanoseconds
            )
        )
    }

    private static func nanoseconds(for time: CMTime, fallback: UInt64) -> UInt64 {
        guard time.isValid && !time.isIndefinite else {
            return fallback
        }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite && seconds >= 0 else {
            return fallback
        }
        return UInt64((seconds * 1_000_000_000).rounded())
    }
}

private struct RawVideoFrame {
    let data: Data
    let width: Int
    let height: Int
    let presentationTime: CMTime
    let duration: CMTime
}

enum MediaFrameSourceError: LocalizedError {
    case cannotDecode(String)
    case noVideoTrack(String)
    case noVideoFrames(String)
    case readerConfigurationFailed
    case missingPixelBuffer

    var errorDescription: String? {
        switch self {
        case .cannotDecode(let name):
            "Could not decode image: \(name)"
        case .noVideoTrack(let name):
            "Video has no video track: \(name)"
        case .noVideoFrames(let name):
            "Video contains no readable frames: \(name)"
        case .readerConfigurationFailed:
            "Could not configure the Apple video reader."
        case .missingPixelBuffer:
            "The Apple video reader returned a frame without pixels."
        }
    }
}
