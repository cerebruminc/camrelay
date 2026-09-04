import Darwin
import Foundation
import CamRelayCore

struct FrameSchedule: Equatable, Sendable {
    let mediaOriginNanoseconds: UInt64
    let uptimeOriginNanoseconds: UInt64

    func targetUptimeNanoseconds(for presentationTimeNanoseconds: UInt64) -> UInt64 {
        let mediaOffset = presentationTimeNanoseconds >= mediaOriginNanoseconds
            ? presentationTimeNanoseconds - mediaOriginNanoseconds
            : 0
        return uptimeOriginNanoseconds + mediaOffset
    }

    func isExpired(
        presentationTimeNanoseconds: UInt64,
        durationNanoseconds: UInt64,
        at uptimeNanoseconds: UInt64
    ) -> Bool {
        targetUptimeNanoseconds(for: presentationTimeNanoseconds) + durationNanoseconds
            <= uptimeNanoseconds
    }
}

final class FrameServer: @unchecked Sendable {
    private static let protocolMagic: UInt32 = 0x4352_4633 // CRF3
    private static let frameClientRole: UInt8 = 0x46 // F
    private static let controlClientRole: UInt8 = 0x43 // C

    let playback: PlaybackEngine
    private let acceptQueue = DispatchQueue(label: "org.camrelay.frameserver.accept")
    private let streamQueue = DispatchQueue(label: "org.camrelay.frameserver.stream")
    private let controlQueue = DispatchQueue(
        label: "org.camrelay.frameserver.control",
        attributes: .concurrent
    )
    private let workerGroup = DispatchGroup()
    private let stateLock = NSLock()
    private let pacingSemaphore = DispatchSemaphore(value: 0)
    private var listeningSocket: Int32 = -1
    private var frameClients: [Int32: FrameClient] = [:]
    private var controlClientSockets: Set<Int32> = []
    private var stopped = false
    private var originUptime: UInt64 = 0

    private(set) var port: UInt16 = 0

    init(playback: PlaybackEngine) {
        self.playback = playback
    }

    var elapsedTime: UInt64 {
        stateLock.withLock {
            originUptime == 0 ? 0 : DispatchTime.now().uptimeNanoseconds - originUptime
        }
    }

    func receiverCounts(for generation: UInt64) -> (connected: Int, acknowledged: Int) {
        let clients = stateLock.withLock { Array(frameClients.values) }
        return (clients.count, clients.filter { $0.acknowledgedGeneration >= generation }.count)
    }

    func waitForFrame(generation: UInt64, timeout: Double) throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        while DispatchTime.now().uptimeNanoseconds < deadline {
            guard !isStopped else { throw RelayError("Relay stopped while waiting for a frame.") }
            let state = playback.snapshot(at: elapsedTime)
            guard state.generation == generation else {
                throw RelayError("Selection was superseded while waiting for a frame.")
            }
            if let error = state.error { throw RelayError(error) }
            let counts = receiverCounts(for: generation)
            if counts.connected > 0 && counts.acknowledged == counts.connected { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw RelayError("Timed out waiting for generation \(generation) to reach every connected frame receiver. The selection remains active.")
    }

    func start() throws {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw FrameServerError.systemCall("socket", errno)
        }

        var noSigPipe: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let error = errno
            close(socketDescriptor)
            throw FrameServerError.systemCall("bind", error)
        }
        guard listen(socketDescriptor, SOMAXCONN) == 0 else {
            let error = errno
            close(socketDescriptor)
            throw FrameServerError.systemCall("listen", error)
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketDescriptor, $0, &boundLength)
            }
        }
        guard nameResult == 0 else {
            let error = errno
            close(socketDescriptor)
            throw FrameServerError.systemCall("getsockname", error)
        }

        listeningSocket = socketDescriptor
        port = UInt16(bigEndian: boundAddress.sin_port)
        stateLock.withLock { originUptime = DispatchTime.now().uptimeNanoseconds }

        workerGroup.enter()
        acceptQueue.async { [self] in
            acceptClients()
            workerGroup.leave()
        }
        workerGroup.enter()
        streamQueue.async { [self] in
            streamFrames()
            workerGroup.leave()
        }
    }

    func stop() {
        let state = stateLock.withLock {
            () -> (listener: Int32, frameClients: [FrameClient], controlClients: [Int32])? in
            guard !stopped else { return nil }
            stopped = true
            let clients = Array(frameClients.values)
            let controls = Array(controlClientSockets)
            frameClients.removeAll()
            controlClientSockets.removeAll()
            let listener = listeningSocket
            listeningSocket = -1
            return (listener, clients, controls)
        }
        guard let state else { return }

        for client in state.frameClients {
            client.stop()
        }
        pacingSemaphore.signal()
        for descriptor in state.controlClients {
            shutdown(descriptor, SHUT_RDWR)
        }
        let currentListener = state.listener
        if currentListener >= 0 {
            shutdown(currentListener, SHUT_RDWR)
            close(currentListener)
        }
        workerGroup.wait()
        for descriptor in state.controlClients {
            close(descriptor)
        }
    }

    private func acceptClients() {
        while !isStopped {
            let descriptor = accept(listeningSocket, nil, nil)
            if descriptor < 0 {
                if !isStopped {
                    FileHandle.standardError.write(Data("camrelay: frame receiver connection failed: \(String(cString: strerror(errno)))\n".utf8))
                }
                return
            }

            var noSigPipe: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))

            var receiveTimeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &receiveTimeout,
                socklen_t(MemoryLayout.size(ofValue: receiveTimeout))
            )

            guard let role = readClientRole(from: descriptor) else {
                close(descriptor)
                continue
            }
            switch role {
            case Self.frameClientRole:
                do {
                    receiveTimeout = timeval(tv_sec: 0, tv_usec: 0)
                    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout.size(ofValue: receiveTimeout)))
                    try write(headerData(), to: descriptor)
                    let client = FrameClient(
                        descriptor: descriptor,
                        workerGroup: workerGroup
                    ) { [weak self] descriptor in
                        self?.removeFrameClient(descriptor)
                    }
                    guard addFrameClient(client) else {
                        close(descriptor)
                        continue
                    }
                    client.start()
                } catch {
                    close(descriptor)
                }
            case Self.controlClientRole:
                do {
                    try write(Data([Self.controlClientRole]), to: descriptor)
                    receiveTimeout = timeval(tv_sec: 0, tv_usec: 0)
                    setsockopt(
                        descriptor,
                        SOL_SOCKET,
                        SO_RCVTIMEO,
                        &receiveTimeout,
                        socklen_t(MemoryLayout.size(ofValue: receiveTimeout))
                    )
                    guard addControlClient(descriptor) else {
                        close(descriptor)
                        continue
                    }
                    monitorControlClient(descriptor)
                } catch {
                    close(descriptor)
                }
            default:
                close(descriptor)
            }
        }
    }

    private func streamFrames() {
        let fps = UInt64(playback.format.framesPerSecond)
        let schedule = FrameSchedule(mediaOriginNanoseconds: 0, uptimeOriginNanoseconds: originUptime)
        var index: UInt64 = 0
        while !isStopped {
            let time = index * 1_000_000_000 / fps
            let duration = (index + 1) * 1_000_000_000 / fps - time
            _ = pacingSemaphore.wait(timeout: DispatchTime(uptimeNanoseconds: schedule.targetUptimeNanoseconds(for: time)))
            guard !isStopped else { return }
            if schedule.isExpired(presentationTimeNanoseconds: time, durationNanoseconds: duration, at: DispatchTime.now().uptimeNanoseconds) {
                index = max(index + 1, elapsedTime * fps / 1_000_000_000)
                continue
            }
            let frame = playback.frame(at: time, duration: duration)
            let clients = stateLock.withLock { Array(frameClients.values) }
            for client in clients { client.offer(frame) }
            index += 1
        }
    }

    private func readClientRole(from descriptor: Int32) -> UInt8? {
        var role: UInt8 = 0
        let count = withUnsafeMutableBytes(of: &role) { buffer in
            recv(descriptor, buffer.baseAddress, 1, 0)
        }
        return count == 1 ? role : nil
    }

    private func addFrameClient(_ client: FrameClient) -> Bool {
        stateLock.withLock {
            guard !stopped else { return false }
            frameClients[client.descriptor] = client
            return true
        }
    }

    private func removeFrameClient(_ descriptor: Int32) {
        _ = stateLock.withLock { frameClients.removeValue(forKey: descriptor) }
    }

    private func addControlClient(_ descriptor: Int32) -> Bool {
        stateLock.withLock {
            guard !stopped else { return false }
            controlClientSockets.insert(descriptor)
            return true
        }
    }

    private func monitorControlClient(_ descriptor: Int32) {
        workerGroup.enter()
        controlQueue.async { [self] in
            var byte: UInt8 = 0
            while recv(descriptor, &byte, 1, 0) > 0 {}
            let removed = stateLock.withLock { controlClientSockets.remove(descriptor) != nil }
            if removed {
                close(descriptor)
            }
            workerGroup.leave()
        }
    }

    private func headerData() -> Data {
        let values = [
            Self.protocolMagic.bigEndian,
            UInt32(playback.format.width).bigEndian,
            UInt32(playback.format.height).bigEndian,
            UInt32(playback.format.bytesPerRow).bigEndian,
            UInt32(playback.format.framesPerSecond).bigEndian,
        ]
        return values.withUnsafeBytes { Data($0) }
    }

    private func write(_ data: Data, to descriptor: Int32) throws {
        try writeAll(data, to: descriptor)
    }

    var isStopped: Bool {
        stateLock.withLock { stopped }
    }
}

private final class FrameClient: @unchecked Sendable {
    let descriptor: Int32

    private let queue: DispatchQueue
    private let workerGroup: DispatchGroup
    private let onDisconnect: @Sendable (Int32) -> Void
    private let stateLock = NSLock()
    private let frameReady = DispatchSemaphore(value: 0)
    private var pendingFrame: PlaybackFrame?
    private var stopped = false
    private var acknowledged: UInt64 = 0
    private var sentGeneration: UInt64 = 0
    private let acknowledgementQueue = DispatchQueue(label: "org.camrelay.frameserver.acknowledgements")
    private let acknowledgementGroup = DispatchGroup()

    var acknowledgedGeneration: UInt64 { stateLock.withLock { acknowledged } }

    init(
        descriptor: Int32,
        workerGroup: DispatchGroup,
        onDisconnect: @escaping @Sendable (Int32) -> Void
    ) {
        self.descriptor = descriptor
        self.workerGroup = workerGroup
        self.onDisconnect = onDisconnect
        queue = DispatchQueue(label: "org.camrelay.frameserver.client.\(descriptor)")
    }

    func start() {
        workerGroup.enter()
        acknowledgementGroup.enter()
        acknowledgementQueue.async { [self] in
            readAcknowledgements()
            acknowledgementGroup.leave()
        }
        queue.async { [self] in
            sendFrames()
            acknowledgementGroup.wait()
            close(descriptor)
            onDisconnect(descriptor)
            workerGroup.leave()
        }
    }

    func offer(_ frame: PlaybackFrame) {
        let shouldSignal = stateLock.withLock {
            guard !stopped else { return false }
            let wasEmpty = pendingFrame == nil
            pendingFrame = frame
            return wasEmpty
        }
        if shouldSignal {
            frameReady.signal()
        }
    }

    func stop() {
        let shouldStop = stateLock.withLock {
            guard !stopped else { return false }
            stopped = true
            pendingFrame = nil
            return true
        }
        if shouldStop {
            shutdown(descriptor, SHUT_RDWR)
            frameReady.signal()
        }
    }

    private func sendFrames() {
        while true {
            frameReady.wait()
            let frame = stateLock.withLock { () -> PlaybackFrame? in
                guard !stopped else { return nil }
                let frame = pendingFrame
                pendingFrame = nil
                return frame
            }
            guard let frame else { break }
            do {
                stateLock.withLock { sentGeneration = frame.generation }
                let frameHeader = [
                    frame.generation.bigEndian,
                    frame.media.presentationTimeNanoseconds.bigEndian,
                    frame.media.durationNanoseconds.bigEndian,
                ]
                try frameHeader.withUnsafeBytes {
                    try writeAll(Data($0), to: descriptor)
                }
                try writeAll(frame.media.data, to: descriptor)
            } catch {
                stateLock.withLock {
                    stopped = true
                    pendingFrame = nil
                }
                break
            }
        }
        shutdown(descriptor, SHUT_RDWR)
    }

    private func readAcknowledgements() {
        while true {
            var value: UInt64 = 0
            let received = withUnsafeMutableBytes(of: &value) { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = recv(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { return false }
                    offset += count
                }
                return true
            }
            guard received else { break }
            let generation = UInt64(bigEndian: value)
            let valid = stateLock.withLock {
                guard generation > 0, generation <= sentGeneration, generation >= acknowledged else { return false }
                acknowledged = generation
                return true
            }
            if !valid { break }
        }
        stop()
    }
}

private func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { buffer in
        guard var pointer = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            return
        }
        var remaining = buffer.count
        while remaining > 0 {
            let count = Darwin.send(descriptor, pointer, remaining, 0)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else {
                throw FrameServerError.systemCall("send", errno)
            }
            remaining -= count
            pointer = pointer.advanced(by: count)
        }
    }
}

enum FrameServerError: LocalizedError {
    case systemCall(String, Int32)
    case unexpectedFrameSize(Int, Int)

    var errorDescription: String? {
        switch self {
        case .systemCall(let name, let code):
            "\(name) failed: \(String(cString: strerror(code)))"
        case .unexpectedFrameSize(let actual, let expected):
            "Decoded frame has \(actual) bytes; expected \(expected)."
        }
    }
}
