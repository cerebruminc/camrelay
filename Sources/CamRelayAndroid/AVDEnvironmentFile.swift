import CamRelayCore
import Foundation

struct AVDEnvironmentFile: Sendable {
    let url: URL
    let sceneMode: String
    private let contents: Data?
    private let permissions: Int?

    init(avdDirectory: URL, fileManager: FileManager = .default) throws {
        url = avdDirectory.appendingPathComponent("environment.ini")
        guard fileManager.fileExists(atPath: url.path) else {
            sceneMode = "none"
            contents = nil
            permissions = nil
            return
        }
        do {
            let original = try Data(contentsOf: url)
            contents = original
            permissions = (try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
            guard let text = String(data: original, encoding: .utf8) else {
                throw RelayError("The environment file is not UTF-8.")
            }
            if let configured = parseINI(text)["scene.mode"], !configured.isEmpty {
                sceneMode = configured
            } else {
                sceneMode = "none"
            }
        } catch {
            throw RelayError("Could not read \(url.path): \(error.localizedDescription)")
        }
    }

    func restore(fileManager: FileManager = .default) throws {
        do {
            if let contents {
                try contents.write(to: url, options: .atomic)
                if let permissions {
                    try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
                }
            } else if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            throw RelayError("Could not restore \(url.path): \(error.localizedDescription)")
        }
    }
}
