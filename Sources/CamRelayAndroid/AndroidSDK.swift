import CamRelayCore
import Foundation

public struct AndroidSDK: Equatable, Sendable {
    public let rootURL: URL
    public let emulatorURL: URL
    public let adbURL: URL
    public let avdHomeURL: URL

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        var roots: [String] = []
        for key in ["ANDROID_SDK_ROOT", "ANDROID_HOME"] {
            if let value = environment[key], !value.isEmpty, !roots.contains(value) {
                roots.append(value)
            }
        }
        if let home = environment["HOME"], !home.isEmpty {
            roots.append((home as NSString).appendingPathComponent("Library/Android/sdk"))
        }

        guard let root = roots.lazy.map({ URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
            .first(where: {
                fileManager.isExecutableFile(atPath: $0.appendingPathComponent("emulator/emulator").path)
                    && fileManager.isExecutableFile(atPath: $0.appendingPathComponent("platform-tools/adb").path)
            }) else {
            throw RelayError("Android SDK not found. Set ANDROID_SDK_ROOT to an SDK containing emulator/emulator and platform-tools/adb.")
        }

        rootURL = root.standardizedFileURL
        emulatorURL = rootURL.appendingPathComponent("emulator/emulator")
        adbURL = rootURL.appendingPathComponent("platform-tools/adb")

        if let home = environment["ANDROID_AVD_HOME"], !home.isEmpty {
            avdHomeURL = URL(fileURLWithPath: (home as NSString).expandingTildeInPath).standardizedFileURL
        } else if let home = environment["ANDROID_USER_HOME"], !home.isEmpty {
            avdHomeURL = URL(fileURLWithPath: (home as NSString).expandingTildeInPath)
                .appendingPathComponent("avd").standardizedFileURL
        } else if let home = environment["HOME"], !home.isEmpty {
            avdHomeURL = URL(fileURLWithPath: home)
                .appendingPathComponent(".android/avd").standardizedFileURL
        } else {
            throw RelayError("Android AVD home not found. Set ANDROID_AVD_HOME or HOME.")
        }
    }

    public func avdDirectory(named name: String, fileManager: FileManager = .default) throws -> URL {
        let descriptorURL = avdHomeURL.appendingPathComponent("\(name).ini")
        if let text = try? String(contentsOf: descriptorURL, encoding: .utf8) {
            let values = parseINI(text)
            if let path = values["path"], !path.isEmpty {
                let directory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
                if fileManager.fileExists(atPath: directory.path) { return directory }
            }
            if let relativePath = values["path.rel"], !relativePath.isEmpty {
                let directory = avdHomeURL.deletingLastPathComponent()
                    .appendingPathComponent(relativePath).standardizedFileURL
                if fileManager.fileExists(atPath: directory.path) { return directory }
            }
        }

        let conventionalURL = avdHomeURL.appendingPathComponent("\(name).avd")
        guard fileManager.fileExists(atPath: conventionalURL.path) else {
            throw RelayError("Could not locate files for Android AVD \(name) under \(avdHomeURL.path).")
        }
        return conventionalURL.standardizedFileURL
    }
}

func parseINI(_ text: String) -> [String: String] {
    var values: [String: String] = [:]
    for line in text.split(whereSeparator: \Character.isNewline) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix(";"),
              let separator = trimmed.firstIndex(of: "=") else { continue }
        let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
        let value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        values[key] = value
    }
    return values
}
