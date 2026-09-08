#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// Lock files retain their inode after release so competing processes lock the same object.
public final class RelayLease: @unchecked Sendable {
    private let descriptor: Int32

    public init(key: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !key.isEmpty, key.utf8.count <= 128,
              key.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              key.first != "-" else {
            throw RelayError("Relay lease name contains unsupported characters.")
        }
        let directory = "/tmp/camrelay-\(getuid())"
        if mkdir(directory, 0o700) != 0 && errno != EEXIST {
            throw leaseSystemError("create control directory")
        }
        var directoryInfo = stat()
        guard lstat(directory, &directoryInfo) == 0,
              directoryInfo.st_mode & S_IFMT == S_IFDIR,
              directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & 0o077 == 0 else {
            throw RelayError("CamRelay's control directory must be owned by the current user and accessible only to that user: \(directory)")
        }

        let path = "\(directory)/\(key).lock"
        let fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw leaseSystemError("open relay lock") }
        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(),
              info.st_nlink == 1,
              info.st_mode & 0o077 == 0 else {
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

private func leaseSystemError(_ operation: String) -> RelayError {
    RelayError("Could not \(operation): \(String(cString: strerror(errno)))")
}
