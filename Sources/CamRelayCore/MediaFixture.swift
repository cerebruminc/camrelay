import Foundation

public struct MediaFixture: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case image
        case video
    }

    public let url: URL
    public let kind: Kind

    public init(path: String, fileManager: FileManager = .default) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw MediaFixtureError.fileNotFound(path)
        }

        let fileExtension = url.pathExtension.lowercased()
        guard let kind = Self.kind(forExtension: fileExtension) else {
            throw MediaFixtureError.unsupportedFormat(fileExtension.isEmpty ? "(none)" : fileExtension)
        }

        self.url = url
        self.kind = kind
    }

    public static func kind(forExtension fileExtension: String) -> Kind? {
        switch fileExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp":
            .image
        case "mp4", "mov", "m4v":
            .video
        default:
            nil
        }
    }
}

public enum MediaFixtureError: LocalizedError, Equatable {
    case fileNotFound(String)
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            "Media file not found: \(path)"
        case .unsupportedFormat(let fileExtension):
            "Unsupported media format: \(fileExtension)"
        }
    }
}
