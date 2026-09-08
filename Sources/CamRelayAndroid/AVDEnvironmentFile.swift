import CamRelayCore
import Foundation

final class AVDEnvironmentFile: @unchecked Sendable {
    let url: URL

    private let originalData: Data?
    private let originalPermissions: NSNumber?
    private let lock = NSLock()
    private var restored = false

    init(avdDirectory: URL, imageURL: URL, fileManager: FileManager = .default) throws {
        guard !imageURL.path.contains("\n"), !imageURL.path.contains("\r") else {
            throw RelayError("Android fixture paths cannot contain line breaks.")
        }
        url = avdDirectory.appendingPathComponent("environment.ini")
        originalData = fileManager.contents(atPath: url.path)
        originalPermissions = try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber

        let contents = Data("scene.mode = imagefile:\(imageURL.path)\n".utf8)
        do {
            try contents.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            let preparationError = error
            do { try restore(fileManager: fileManager) }
            catch {
                throw RelayError("Could not prepare \(url.path): \(preparationError.localizedDescription). Cleanup also failed: \(error.localizedDescription)")
            }
            throw RelayError("Could not prepare \(url.path): \(preparationError.localizedDescription)")
        }
    }

    func restore(fileManager: FileManager = .default) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !restored else { return }

        do {
            if let originalData {
                try originalData.write(to: url, options: .atomic)
                if let originalPermissions {
                    try fileManager.setAttributes([.posixPermissions: originalPermissions], ofItemAtPath: url.path)
                }
            } else if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            restored = true
        } catch {
            throw RelayError("Could not restore \(url.path): \(error.localizedDescription)")
        }
    }
}
