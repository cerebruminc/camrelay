import AVFoundation
import CamRelayCore
import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import CamRelayIOS

@Suite("Media frame source")
struct MediaFrameSourceTests {
    @Test("identity video metadata keeps the encoded dimensions")
    func identityDisplayGeometry() throws {
        let geometry = try VideoDisplayGeometry(
            naturalSize: CGSize(width: 640, height: 360),
            preferredTransform: .identity
        )

        #expect(geometry.width == 640)
        #expect(geometry.height == 360)
        #expect(geometry.transform == .identity)
    }

    @Test("rotation metadata produces upright portrait pixels")
    func rotatedDisplayGeometry() throws {
        let geometry = try VideoDisplayGeometry(
            naturalSize: CGSize(width: 640, height: 360),
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
        )
        let outputBounds = CGRect(x: 0, y: 0, width: 640, height: 360)
            .applying(geometry.transform)
            .standardized

        #expect(geometry.width == 360)
        #expect(geometry.height == 640)
        #expect(abs(outputBounds.minX) < 0.001)
        #expect(abs(outputBounds.minY) < 0.001)
        #expect(abs(outputBounds.width - 360) < 0.001)
        #expect(abs(outputBounds.height - 640) < 0.001)
    }

    @Test("video loops preserve frame order and strictly increasing timestamps")
    func videoLoops() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "camrelay-loop-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeVideoFixture(to: url)

        let source = try await MediaFrameSource(fixture: MediaFixture(path: url.path))
        var previousTime: UInt64?
        var firstLoopPixels: [Data] = []
        for index in 0..<30 {
            let frame = try source.nextFrame()
            #expect(frame.data.count == source.format.frameByteCount)
            #expect(frame.durationNanoseconds > 0)
            let expectedTime = UInt64((Double(index) * 1_000_000_000 / 30).rounded())
            #expect(frame.presentationTimeNanoseconds == expectedTime)
            if let previousTime {
                #expect(frame.presentationTimeNanoseconds > previousTime)
            }
            previousTime = frame.presentationTimeNanoseconds
            if index < 3 {
                firstLoopPixels.append(frame.data)
            } else {
                let matchesExpectedFrame = frame.data == firstLoopPixels[index % 3]
                #expect(matchesExpectedFrame)
            }
        }

        try source.restart()
        for index in 0..<6 {
            let frame = try source.nextFrame()
            let expectedTime = UInt64((Double(index) * 1_000_000_000 / 30).rounded())
            #expect(frame.presentationTimeNanoseconds == expectedTime)
            let matchesExpectedFrame = frame.data == firstLoopPixels[index % 3]
            #expect(matchesExpectedFrame)
        }
    }

    private func writeVideoFixture(to url: URL) async throws {
        let width = 1280
        let height = 720
        let framesPerSecond: Int32 = 30
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
        guard writer.canAdd(input) else { throw VideoFixtureError.cannotConfigureWriter }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? VideoFixtureError.cannotConfigureWriter
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            writer.cancelWriting()
            throw VideoFixtureError.cannotAllocatePixelBuffer
        }

        for index in 0..<3 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else {
                    throw writer.error ?? VideoFixtureError.cannotWriteFrame
                }
                try await Task.sleep(for: .milliseconds(1))
            }
            var optionalBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
                  let buffer = optionalBuffer else {
                writer.cancelWriting()
                throw VideoFixtureError.cannotAllocatePixelBuffer
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                memset(baseAddress, Int32(index * 80), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: Int64(index), timescale: framesPerSecond)
            ) else {
                writer.cancelWriting()
                throw writer.error ?? VideoFixtureError.cannotWriteFrame
            }
        }

        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 3, timescale: framesPerSecond))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? VideoFixtureError.cannotWriteFrame
        }
    }
}

private enum VideoFixtureError: Error {
    case cannotConfigureWriter
    case cannotAllocatePixelBuffer
    case cannotWriteFrame
}
