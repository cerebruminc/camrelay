import CamRelayCore
import Darwin
import Foundation
import XCTest
@testable import CamRelayIOS

final class FrameTransportTests: XCTestCase {
    func testSwitchRequiresRuntimeAcknowledgementAndPreservesConnection() throws {
        let server = try makeServer()
        try server.start()
        defer { server.stop() }
        let client = try FrameTestClient(port: server.port)
        defer { client.close() }
        XCTAssertEqual(client.header[0], 0x43524633)
        let first = try client.frame()
        XCTAssertEqual(first.generation, 1)
        XCTAssertThrowsError(try server.waitForFrame(generation: 1, timeout: 0.05))
        try client.acknowledge(1)
        try server.waitForFrame(generation: 1, timeout: 1)

        let replacement = try PreparedFixture(name: "pattern", source: TransportSource(value: 200))
        let generation = try server.playback.select(replacement, at: server.elapsedTime, paused: true)
        var selected = try client.frame()
        while selected.generation != generation { selected = try client.frame() }
        XCTAssertEqual(selected.pixels.first, 200)
        XCTAssertGreaterThan(selected.time, first.time)
        try client.acknowledge(generation)
        try server.waitForFrame(generation: generation, timeout: 1)
        XCTAssertEqual(server.receiverCounts(for: generation).connected, 1)
        let held = try client.frame()
        XCTAssertGreaterThan(held.time, selected.time)
        XCTAssertEqual(held.pixels, selected.pixels)
    }

    func testWaitNeedsAtLeastOneReceiverAndFailsForSupersededSelection() throws {
        let server = try makeServer()
        try server.start()
        defer { server.stop() }
        XCTAssertThrowsError(try server.waitForFrame(generation: 1, timeout: 0.03))
        server.playback.setPaused(true, at: server.elapsedTime)
        XCTAssertThrowsError(try server.waitForFrame(generation: 1, timeout: 1))
    }

    func testSlowReceiverDoesNotBlockActiveReceiverOrCleanup() throws {
        let server = try makeServer(size: 1024)
        try server.start()
        let slow = try FrameTestClient(port: server.port)
        defer { slow.close() }
        let active = try FrameTestClient(port: server.port)
        defer { active.close() }
        var lastTime: UInt64 = 0
        for _ in 0..<6 {
            let frame = try active.frame()
            XCTAssertGreaterThan(frame.time, lastTime)
            lastTime = frame.time
        }
        try active.acknowledge(1)
        XCTAssertThrowsError(try server.waitForFrame(generation: 1, timeout: 0.05))
        let start = Date()
        server.stop()
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testTwoReceiversMustBothAcknowledgeAndReconnectCanAcknowledgeSameGeneration() throws {
        let server = try makeServer()
        try server.start()
        defer { server.stop() }
        let first = try FrameTestClient(port: server.port)
        defer { first.close() }
        let second = try FrameTestClient(port: server.port)
        _ = try first.frame()
        _ = try second.frame()
        try first.acknowledge(1)
        XCTAssertThrowsError(try server.waitForFrame(generation: 1, timeout: 0.05))
        try second.acknowledge(1)
        try server.waitForFrame(generation: 1, timeout: 1)
        second.close()
        let reconnected = try FrameTestClient(port: server.port)
        defer { reconnected.close() }
        _ = try reconnected.frame()
        try reconnected.acknowledge(1)
        try server.waitForFrame(generation: 1, timeout: 1)
    }

    private func makeServer(size: Int = 2) throws -> FrameServer {
        let source = TransportSource(value: 10, size: size)
        return try FrameServer(playback: PlaybackEngine(initial: PreparedFixture(name: "colors", source: source)))
    }
}

private final class TransportSource: FrameSource {
    let format: FrameFormat
    private let pixels: Data
    private var index: UInt64 = 0

    init(value: UInt8, size: Int = 2) {
        format = FrameFormat(width: size, height: size, bytesPerRow: size * 4, framesPerSecond: 30)
        pixels = Data(repeating: value, count: format.frameByteCount)
    }

    func nextFrame() -> MediaFrame {
        let time = index * 1_000_000_000 / 30
        index += 1
        return MediaFrame(data: pixels, presentationTimeNanoseconds: time, durationNanoseconds: index * 1_000_000_000 / 30 - time)
    }

    func restart() { index = 0 }
}

private final class FrameTestClient {
    let header: [UInt32]
    private var fd: Int32

    init(port: UInt16) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw RelayError("socket failed") }
        fd = descriptor
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { Darwin.close(descriptor); throw RelayError("connect failed") }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var role: UInt8 = 0x46
        guard send(descriptor, &role, 1, 0) == 1 else { Darwin.close(descriptor); throw RelayError("role failed") }
        let data = try Self.read(descriptor, count: 20)
        header = data.withUnsafeBytes { bytes in
            (0..<5).map { UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)) }
        }
    }

    func frame() throws -> (generation: UInt64, time: UInt64, pixels: Data) {
        let timing = try Self.read(fd, count: 24)
        let values = timing.withUnsafeBytes { bytes in
            (0..<3).map { UInt64(bigEndian: bytes.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self)) }
        }
        guard values[2] > 0 else { throw RelayError("zero frame duration") }
        return (values[0], values[1], try Self.read(fd, count: Int(header[2] * header[3])))
    }

    func acknowledge(_ generation: UInt64) throws {
        var value = generation.bigEndian
        guard send(fd, &value, 8, 0) == 8 else { throw RelayError("ack failed") }
    }

    func close() {
        if fd >= 0 { shutdown(fd, SHUT_RDWR); Darwin.close(fd); fd = -1 }
    }

    deinit { close() }

    private static func read(_ fd: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let received = recv(fd, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                guard received > 0 else { throw RelayError("frame receive failed") }
                offset += received
            }
        }
        return data
    }
}
