import AVFoundation
import CamRelayCore
import CoreGraphics
import CoreImage
import Foundation

final class AndroidMediaPreparer: @unchecked Sendable {
    private struct Fingerprint: Equatable {
        let size: UInt64
        let modificationDate: Date?
    }

    private struct CachedMedia {
        let fingerprint: Fingerprint
        let media: MediaFixture
    }

    private let fileManager: FileManager
    private let directory: URL
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let lock = NSLock()
    private var cache: [URL: CachedMedia] = [:]
    private var cleanedUp = false

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("camrelay-android-media-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            throw RelayError("Could not create temporary Android media: \(error.localizedDescription)")
        }
    }

    deinit { cleanup() }

    func prepare(_ source: MediaFixture) throws -> MediaFixture {
        try lock.withLock {
            guard !cleanedUp else { throw RelayError("The Android media session has ended.") }
            let fingerprint = try fingerprint(for: source.url)
            if let cached = cache[source.url], cached.fingerprint == fingerprint {
                return cached.media
            }

            let output = directory.appendingPathComponent("\(UUID().uuidString).\(source.kind == .image ? "png" : "mp4")")
            do {
                switch source.kind {
                case .image:
                    try prepareImage(source.url, at: output)
                case .video:
                    try runBlocking { try await self.prepareVideo(source.url, at: output) }
                }
                let media = try MediaFixture(path: output.path)
                cache[source.url] = CachedMedia(fingerprint: fingerprint, media: media)
                return media
            } catch {
                try? fileManager.removeItem(at: output)
                throw RelayError("Could not prepare Android fixture \(source.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    func cleanup() {
        lock.withLock {
            guard !cleanedUp else { return }
            try? fileManager.removeItem(at: directory)
            cache.removeAll()
            cleanedUp = true
        }
    }

    func leaveFilesInPlace() -> URL {
        lock.withLock {
            cleanedUp = true
            cache.removeAll()
            return directory
        }
    }

    private func fingerprint(for url: URL) throws -> Fingerprint {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return Fingerprint(
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date
        )
    }

    private func prepareImage(_ source: URL, at output: URL) throws {
        guard let image = CIImage(contentsOf: source, options: [.applyOrientationProperty: true]),
              image.extent.width.isFinite, image.extent.height.isFinite,
              image.extent.width > 0, image.extent.height > 0 else {
            throw AndroidMediaPreparationError.cannotDecode(source.lastPathComponent)
        }
        let canvas = CGRect(origin: .zero, size: image.extent.size)
        let prepared = prepare(image, for: canvas)
        try context.writePNGRepresentation(of: prepared, to: output, format: .RGBA8, colorSpace: colorSpace)
    }

    private func prepareVideo(_ source: URL, at output: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw AndroidMediaPreparationError.noVideoTrack(source.lastPathComponent)
        }

        // Core Image's video-buffer coordinates run opposite AVFoundation's display transform.
        let displayTransform = try await track.load(.preferredTransform).inverted()
        let naturalSize = try await track.load(.naturalSize)
        let displayBounds = CGRect(origin: .zero, size: naturalSize)
            .applying(displayTransform).standardized
        guard displayBounds.width.isFinite, displayBounds.height.isFinite,
              displayBounds.width > 0, displayBounds.height > 0 else {
            throw AndroidMediaPreparationError.invalidDimensions(source.lastPathComponent)
        }
        let width = evenDimension(displayBounds.width)
        let height = evenDimension(displayBounds.height)
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw AndroidMediaPreparationError.readerConfigurationFailed }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
        guard writer.canAdd(writerInput) else { throw AndroidMediaPreparationError.writerConfigurationFailed }
        writer.add(writerInput)
        guard writer.startWriting() else {
            throw writer.error ?? AndroidMediaPreparationError.writerConfigurationFailed
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            writer.cancelWriting()
            throw reader.error ?? AndroidMediaPreparationError.readerConfigurationFailed
        }
        guard let pool = adaptor.pixelBufferPool else {
            reader.cancelReading()
            writer.cancelWriting()
            throw AndroidMediaPreparationError.writerConfigurationFailed
        }

        let normalizeOrientation = displayTransform.concatenating(
            CGAffineTransform(translationX: -displayBounds.minX, y: -displayBounds.minY)
        )
        var firstPresentationTime: CMTime?
        var endTime = CMTime.zero
        var frameCount = 0

        while let sample = readerOutput.copyNextSampleBuffer() {
            guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample) else {
                reader.cancelReading()
                writer.cancelWriting()
                throw AndroidMediaPreparationError.missingPixelBuffer
            }
            while !writerInput.isReadyForMoreMediaData {
                guard writer.status == .writing else {
                    reader.cancelReading()
                    throw writer.error ?? AndroidMediaPreparationError.writerFailed
                }
                try await Task.sleep(for: .milliseconds(1))
            }

            var destinationBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destinationBuffer) == kCVReturnSuccess,
                  let destinationBuffer else {
                reader.cancelReading()
                writer.cancelWriting()
                throw AndroidMediaPreparationError.cannotAllocatePixelBuffer
            }

            let oriented = CIImage(cvPixelBuffer: sourceBuffer).transformed(by: normalizeOrientation)
            context.render(prepare(oriented, for: canvas), to: destinationBuffer, bounds: canvas, colorSpace: colorSpace)

            let sourceTime = CMSampleBufferGetPresentationTimeStamp(sample)
            if firstPresentationTime == nil { firstPresentationTime = sourceTime }
            let presentationTime = CMTimeSubtract(sourceTime, firstPresentationTime ?? sourceTime)
            guard adaptor.append(destinationBuffer, withPresentationTime: presentationTime) else {
                reader.cancelReading()
                writer.cancelWriting()
                throw writer.error ?? AndroidMediaPreparationError.writerFailed
            }
            let duration = CMSampleBufferGetDuration(sample)
            endTime = duration.isValid && duration > .zero
                ? CMTimeAdd(presentationTime, duration)
                : presentationTime
            frameCount += 1
        }

        guard frameCount > 0 else {
            writerInput.markAsFinished()
            writer.cancelWriting()
            throw AndroidMediaPreparationError.noVideoFrames(source.lastPathComponent)
        }
        guard reader.status == .completed else {
            writerInput.markAsFinished()
            writer.cancelWriting()
            throw reader.error ?? AndroidMediaPreparationError.readerFailed
        }

        writerInput.markAsFinished()
        if endTime > .zero { writer.endSession(atSourceTime: endTime) }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? AndroidMediaPreparationError.writerFailed
        }
    }

    private func prepare(_ source: CIImage, for canvas: CGRect) -> CIImage {
        let visible = androidEnvironmentVisibleRect(in: canvas)
        let sourceBounds = source.extent.standardized
        let target = androidFittedContentRect(
            sourceAspectRatio: sourceBounds.width / sourceBounds.height,
            in: visible
        )
        let transform = CGAffineTransform(translationX: -sourceBounds.minX, y: -sourceBounds.minY)
            .scaledBy(x: target.width / sourceBounds.width, y: target.height / sourceBounds.height)
            .translatedBy(
                x: target.minX * sourceBounds.width / target.width,
                y: target.minY * sourceBounds.height / target.height
            )
        let fitted = source.transformed(by: transform)
        return fitted.composited(over: CIImage(color: .black)).cropped(to: canvas)
    }
}

private final class BlockingError: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (any Error)?

    func set(_ error: (any Error)?) { lock.withLock { value = error } }
    func get() -> (any Error)? { lock.withLock { value } }
}

private func runBlocking(_ operation: @escaping @Sendable () async throws -> Void) throws {
    let finished = DispatchSemaphore(value: 0)
    let failure = BlockingError()
    Task.detached {
        do { try await operation() }
        catch { failure.set(error) }
        finished.signal()
    }
    finished.wait()
    if let error = failure.get() { throw error }
}

func androidEnvironmentVisibleRect(in canvas: CGRect) -> CGRect {
    // The emulator's environment camera shows this fixed window of scene.mode media.
    let scale: CGFloat = 9.0 / 16.0
    return CGRect(
        x: canvas.minX,
        y: canvas.minY + canvas.height * (1 - scale) / 2,
        width: canvas.width * scale,
        height: canvas.height * scale
    )
}

func androidFittedContentRect(sourceAspectRatio: CGFloat, in visible: CGRect) -> CGRect {
    // Android presents the environment camera as a 3:4 image in portrait orientation.
    let cameraAspectRatio: CGFloat = 3.0 / 4.0
    if sourceAspectRatio < cameraAspectRatio {
        let width = visible.width * sourceAspectRatio / cameraAspectRatio
        return CGRect(x: visible.midX - width / 2, y: visible.minY, width: width, height: visible.height)
    }
    let height = visible.height * cameraAspectRatio / sourceAspectRatio
    return CGRect(x: visible.minX, y: visible.midY - height / 2, width: visible.width, height: height)
}

private func evenDimension(_ value: CGFloat) -> Int {
    let rounded = max(2, Int(value.rounded()))
    return rounded.isMultiple(of: 2) ? rounded : rounded + 1
}

private enum AndroidMediaPreparationError: LocalizedError {
    case cannotDecode(String)
    case noVideoTrack(String)
    case noVideoFrames(String)
    case invalidDimensions(String)
    case readerConfigurationFailed
    case writerConfigurationFailed
    case missingPixelBuffer
    case cannotAllocatePixelBuffer
    case readerFailed
    case writerFailed

    var errorDescription: String? {
        switch self {
        case .cannotDecode(let name): "Could not decode image \(name)."
        case .noVideoTrack(let name): "Video \(name) has no video track."
        case .noVideoFrames(let name): "Video \(name) has no frames."
        case .invalidDimensions(let name): "Video \(name) has invalid dimensions."
        case .readerConfigurationFailed: "Could not configure the video decoder."
        case .writerConfigurationFailed: "Could not configure the temporary video encoder."
        case .missingPixelBuffer: "A decoded video frame has no pixels."
        case .cannotAllocatePixelBuffer: "Could not allocate a temporary video frame."
        case .readerFailed: "Video decoding failed."
        case .writerFailed: "Temporary video encoding failed."
        }
    }
}
