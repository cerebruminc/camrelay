import CamRelayCore
import Darwin
import Foundation

enum ControlPaths {
    static func directory() throws -> String {
        let path = "/tmp/camrelay-\(getuid())"
        if mkdir(path, 0o700) != 0 && errno != EEXIST { throw systemError("create control directory") }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            throw RelayError("CamRelay's control directory must be owned by the current user and accessible only to that user: \(path)")
        }
        return path
    }

    static func socket(session: String) throws -> String {
        try RelayCommand.validateName(session, kind: "Session name")
        return try directory() + "/\(session).sock"
    }
}

/// Lock files retain their inode after release so competing processes lock the same object.
final class RelayLease: @unchecked Sendable {
    private let descriptor: Int32

    init(key: String) throws {
        let path = try ControlPaths.directory() + "/\(key).lock"
        let fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw systemError("open relay lock") }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1, info.st_mode & 0o077 == 0 else {
            close(fd)
            throw RelayError("Unsafe relay lock: \(path)")
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw RelayError("A relay already owns \(key). Stop that relay before starting another.")
        }
        descriptor = fd
    }

    deinit { close(descriptor) }
}

public final class LocalControlServer: @unchecked Sendable {
    private let lease: RelayLease
    private let path: String
    private let listener: Int32
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var clients: Set<Int32> = []
    private var stopped = false

    public init(session: String) throws {
        path = try ControlPaths.socket(session: session)
        lease = try RelayLease(key: "session-\(session)")
        var existing = stat()
        if lstat(path, &existing) == 0 {
            guard existing.st_mode & S_IFMT == S_IFSOCK, existing.st_uid == getuid() else {
                throw RelayError("Refusing to replace a non-socket control path: \(path)")
            }
            // Holding the session lease proves that this endpoint has no live owner.
            guard unlink(path) == 0 else { throw systemError("remove stale control socket") }
        } else if errno != ENOENT {
            throw systemError("inspect control socket")
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw systemError("create control socket") }
        do {
            try withUnixAddress(path) { address, length in
                guard Darwin.bind(fd, address, length) == 0 else { throw systemError("bind control socket") }
            }
        } catch {
            close(fd)
            throw error
        }
        listener = fd
    }

    public func start(
        handler: @escaping @Sendable (RelayControlRequest) async -> RelayControlResponse,
        didStop: @escaping @Sendable () -> Void
    ) throws {
        guard fcntl(listener, F_SETFL, O_NONBLOCK) == 0 else { throw systemError("configure control listener") }
        guard listen(listener, 16) == 0 else { throw systemError("listen on control socket") }
        group.enter()
        DispatchQueue(label: "org.camrelay.control.accept").async { [self] in
            defer { group.leave() }
            while !lock.withLock({ stopped }) {
                var pending = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
                let ready = poll(&pending, 1, 100)
                if ready == 0 || (ready < 0 && errno == EINTR) { continue }
                guard ready > 0, !lock.withLock({ stopped }) else { break }
                let fd = accept(listener, nil, nil)
                if fd < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    break
                }
                // Accepted sockets use blocking, bounded reads even on platforms that inherit flags.
                guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) == 0 else { close(fd); continue }
                let accepted = lock.withLock {
                    guard !stopped else { return false }
                    clients.insert(fd)
                    return true
                }
                guard accepted else { close(fd); break }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    do {
                        configureSocket(fd, timeout: 5)
                        let request = try JSONDecoder().decode(RelayControlRequest.self, from: readMessage(fd))
                        try request.validate()
                        Task {
                            let response = await handler(request)
                            configureSocket(fd, timeout: 5)
                            try? writeMessage(JSONEncoder().encode(response), to: fd)
                            finish(fd)
                            if request.action == .stop && response.error == nil { didStop() }
                        }
                    } catch {
                        try? writeMessage(JSONEncoder().encode(RelayControlResponse(error: error.localizedDescription)), to: fd)
                        finish(fd)
                    }
                }
            }
        }
    }

    private func finish(_ fd: Int32) {
        lock.withLock {
            clients.remove(fd)
            close(fd)
        }
        group.leave()
    }

    public func stop() {
        let shouldStop = lock.withLock {
            guard !stopped else { return false }
            stopped = true
            shutdown(listener, SHUT_RDWR)
            for fd in clients { shutdown(fd, SHUT_RDWR) }
            return true
        }
        guard shouldStop else { return }
        group.wait()
        close(listener)
        unlink(path)
    }

    deinit { stop() }
}

public enum RelayControlClient {
    public static func send(
        _ request: RelayControlRequest, session: String, waitForReady: Bool = false
    ) throws -> RelayControlResponse {
        try request.validate()
        let path = try ControlPaths.socket(session: session)
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(request.timeout * 1_000_000_000)
        repeat {
            do {
                return try transact(request, path: path)
            } catch {
                guard waitForReady, DispatchTime.now().uptimeNanoseconds < deadline else { throw error }
                Thread.sleep(forTimeInterval: 0.05)
            }
        } while true
    }

    private static func transact(_ request: RelayControlRequest, path: String) throws -> RelayControlResponse {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw systemError("create control connection") }
        defer { close(fd) }
        configureSocket(fd, timeout: request.timeout + 2)
        try withUnixAddress(path) { address, length in
            guard connect(fd, address, length) == 0 else {
                throw RelayError("No ready relay at \(path). Start the named session first.")
            }
        }
        try writeMessage(JSONEncoder().encode(request), to: fd)
        return try JSONDecoder().decode(RelayControlResponse.self, from: readMessage(fd))
    }
}

private func withUnixAddress<T>(
    _ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
) throws -> T {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard path.utf8.count < capacity else { throw RelayError("Control socket path is too long.") }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
            path.withCString { source in _ = strlcpy(destination, source, capacity) }
        }
    }
    return try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

private func configureSocket(_ fd: Int32, timeout: Double) {
    var noSigPipe: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))
    var value = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout.size(ofValue: value)))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout.size(ofValue: value)))
}

private func writeMessage(_ data: Data, to fd: Int32) throws {
    guard data.count <= 1_048_576 else { throw RelayError("Control response is too large.") }
    var length = UInt32(data.count).bigEndian
    let prefix = withUnsafeBytes(of: &length) { Data($0) }
    try (prefix + data).withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw systemError("write control message") }
            offset += count
        }
    }
}

private func readMessage(_ fd: Int32) throws -> Data {
    func read(_ count: Int) throws -> Data {
        var result = Data(count: count)
        try result.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let received = recv(fd, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                if received < 0 && errno == EINTR { continue }
                guard received > 0 else { throw RelayError("Control connection closed or timed out.") }
                offset += received
            }
        }
        return result
    }
    let prefix = try read(4)
    let length = prefix.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
    guard length > 0, length <= 1_048_576 else { throw RelayError("Invalid control message length.") }
    return try read(Int(length))
}

private func systemError(_ operation: String) -> RelayError {
    RelayError("Could not \(operation): \(String(cString: strerror(errno)))")
}
