import CamRelayCore
import Foundation
import XCTest
@testable import CamRelayIOS

final class PlaybackEngineTests: XCTestCase {
    func testSwitchKeepsOutputFormatAndContinuousCameraTimestamps() throws {
        let engine = try PlaybackEngine(initial: fixture("colors", fps: 30, values: [10, 20]))
        XCTAssertEqual(engine.frame(at: 0, duration: 10).media.data.first, 10)
        try engine.select(fixture("pattern", fps: 15, values: [100, 200]), at: 1_000_000_000, paused: false)
        let first = engine.frame(at: 1_000_000_000, duration: 10)
        XCTAssertEqual(first.media.presentationTimeNanoseconds, 1_000_000_000)
        XCTAssertEqual(first.media.data.first, 100)
        XCTAssertEqual(first.generation, 2)
        XCTAssertEqual(engine.format.framesPerSecond, 30)
        XCTAssertEqual(engine.frame(at: 1_040_000_000, duration: 10).media.data.first, 100)
        XCTAssertEqual(engine.frame(at: 1_080_000_000, duration: 10).media.data.first, 200)
    }

    func testPausedFramesKeepArrivingWithNewCameraTimestamps() throws {
        let engine = try PlaybackEngine(initial: fixture("colors", values: [10, 20]), paused: true)
        for time in [0, 100_000_000, 500_000_000] as [UInt64] {
            let frame = engine.frame(at: time, duration: 10)
            XCTAssertEqual(frame.media.data.first, 10)
            XCTAssertEqual(frame.media.presentationTimeNanoseconds, time)
        }
        engine.setPaused(false, at: 500_000_000)
        XCTAssertEqual(engine.frame(at: 540_000_000, duration: 10).media.data.first, 20)
    }

    func testLoopAndReplayUseSourceTime() throws {
        let engine = try PlaybackEngine(initial: fixture("colors", fps: 10, values: [10, 20]))
        XCTAssertEqual(engine.frame(at: 150_000_000, duration: 10).media.data.first, 20)
        XCTAssertEqual(engine.frame(at: 250_000_000, duration: 10).media.data.first, 10)
        try engine.select(fixture("colors", fps: 10, values: [10, 20]), at: 250_000_000, paused: true)
        XCTAssertEqual(engine.frame(at: 1_000_000_000, duration: 10).media.data.first, 10)
        XCTAssertEqual(engine.snapshot(at: 1_000_000_000).positionNanoseconds, 0)
    }

    func testAspectFitPreservesEntireSourceAndPadsInsteadOfCropping() throws {
        let target = FakeSource(width: 4, height: 4, fps: 30, values: [0])
        let engine = try PlaybackEngine(initial: PreparedFixture(name: "target", source: target))
        let source = FakeSource(width: 4, height: 2, fps: 30, values: [255])
        try engine.select(PreparedFixture(name: "wide", source: source), at: 0, paused: true)
        let pixels = engine.frame(at: 0, duration: 10).media.data
        XCTAssertEqual(pixels.count, 64)
        XCTAssertEqual(pixels[0], 0)
        XCTAssertEqual(pixels[16], 255)
        XCTAssertEqual(pixels[32], 255)
        XCTAssertEqual(pixels[48], 0)
    }

    private func fixture(_ name: String, fps: Int = 30, values: [UInt8]) throws -> PreparedFixture {
        try PreparedFixture(name: name, source: FakeSource(fps: fps, values: values))
    }
}

private final class FakeSource: FrameSource {
    let format: FrameFormat
    let values: [UInt8]
    private var index: UInt64 = 0

    init(width: Int = 2, height: Int = 2, fps: Int, values: [UInt8]) {
        format = FrameFormat(width: width, height: height, bytesPerRow: width * 4, framesPerSecond: fps)
        self.values = values
    }

    func nextFrame() -> MediaFrame {
        let time = index * 1_000_000_000 / UInt64(format.framesPerSecond)
        let value = values[Int(index % UInt64(values.count))]
        var bytes = Data(repeating: value, count: format.frameByteCount)
        for offset in stride(from: 3, to: bytes.count, by: 4) { bytes[offset] = 255 }
        index += 1
        return MediaFrame(
            data: bytes, presentationTimeNanoseconds: time,
            durationNanoseconds: index * 1_000_000_000 / UInt64(format.framesPerSecond) - time
        )
    }

    func restart() { index = 0 }
}
