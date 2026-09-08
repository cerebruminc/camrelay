import CamRelayCore
import Foundation

struct AVDEnvironmentFile: Sendable {
    let url: URL
    let sceneMode: String

    init(avdDirectory: URL, fileManager: FileManager = .default) throws {
        url = avdDirectory.appendingPathComponent("environment.ini")
        guard fileManager.fileExists(atPath: url.path) else {
            sceneMode = "none"
            return
        }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            if let configured = parseINI(contents)["scene.mode"], !configured.isEmpty {
                sceneMode = configured
            } else {
                sceneMode = "none"
            }
        } catch {
            throw RelayError("Could not read \(url.path): \(error.localizedDescription)")
        }
    }
}
