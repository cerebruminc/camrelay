#if os(Linux)
import CamRelayCore
import Foundation

/// FFmpeg replaces the Apple media frameworks on Linux.
final class AndroidMediaPreparer: @unchecked Sendable {
    private struct Fingerprint: Equatable {
        let size: UInt64
        let modificationDate: Date?
    }

    private let fileManager: FileManager
    private let directory: URL
    private let lock = NSLock()
    private var cache: [URL: (Fingerprint, MediaFixture)] = [:]
    private var cleanedUp = false

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("camrelay-android-media-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            throw RelayError("Could not create temporary Android media: \(error.localizedDescription)")
        }
    }

    deinit { cleanup() }

    func prepare(_ source: MediaFixture) throws -> MediaFixture {
        try lock.withLock {
            guard !cleanedUp else { throw RelayError("The Android media session has ended.") }
            let attributes = try fileManager.attributesOfItem(atPath: source.url.path)
            let fingerprint = Fingerprint(
                size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                modificationDate: attributes[.modificationDate] as? Date
            )
            if let cached = cache[source.url], cached.0 == fingerprint { return cached.1 }
            let output = directory.appendingPathComponent("\(UUID().uuidString).\(source.kind == .image ? "png" : "mp4")")
            do {
                let info = try runTool("ffprobe", arguments: [
                    "-v", "error", "-select_streams", "v:0", "-show_entries",
                    "stream=width,height:stream_side_data=rotation", "-of", "json", source.url.path,
                ])
                let metadata = try JSONDecoder().decode(Probe.self, from: info)
                guard let stream = metadata.streams.first, stream.width > 0, stream.height > 0 else {
                    throw RelayError("Fixture has no decodable video or image stream.")
                }
                let rotation = stream.sideData?.compactMap(\.rotation).first ?? 0
                let sideways = abs(rotation % 180) == 90
                let width = sideways ? stream.height : stream.width
                let height = sideways ? stream.width : stream.height
                let filter = androidMediaFilter(width: width, height: height)
                var arguments = ["-v", "error", "-nostdin", "-i", source.url.path, "-map", "0:v:0", "-vf", filter, "-an"]
                if source.kind == .image {
                    arguments += ["-frames:v", "1", "-update", "1"]
                } else {
                    arguments += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-fps_mode", "passthrough", "-map_metadata", "-1"]
                }
                _ = try runTool("ffmpeg", arguments: arguments + [output.path])
                let prepared = try MediaFixture(path: output.path)
                cache[source.url] = (fingerprint, prepared)
                return prepared
            } catch {
                try? fileManager.removeItem(at: output)
                throw RelayError("Could not prepare Android fixture \(source.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    func cleanup() {
        lock.withLock {
            guard !cleanedUp else { return }
            try? fileManager.removeItem(at: directory)
            cache.removeAll()
            cleanedUp = true
        }
    }

    func leaveFilesInPlace() -> URL {
        lock.withLock {
            cleanedUp = true
            cache.removeAll()
            return directory
        }
    }

    private struct Probe: Decodable {
        let streams: [Stream]
        struct Stream: Decodable {
            let width: Int
            let height: Int
            let sideData: [SideData]?
            enum CodingKeys: String, CodingKey {
                case width, height
                case sideData = "side_data_list"
            }
        }
        struct SideData: Decodable { let rotation: Int? }
    }

    private func runTool(_ name: String, arguments: [String]) throws -> Data {
        let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        guard let executable = searchPath.split(separator: ":").map({
            URL(fileURLWithPath: String($0)).appendingPathComponent(name)
        }).first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            throw RelayError("\(name) is required for Android media on Linux. Install FFmpeg and add it to PATH.")
        }
        return try runLinuxAndroidCommand(
            executable,
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }
}

func androidMediaFilter(width: Int, height: Int) -> String {
    let canvasWidth = max(2, width + width % 2)
    let canvasHeight = max(2, height + height % 2)
    let visibleWidth = Double(canvasWidth) * 9 / 16
    let visibleHeight = Double(canvasHeight) * 9 / 16
    let aspectRatio = Double(width) / Double(height)
    let fittedWidth = aspectRatio < 0.75 ? visibleWidth * aspectRatio / 0.75 : visibleWidth
    let fittedHeight = aspectRatio < 0.75 ? visibleHeight : visibleHeight * 0.75 / aspectRatio
    let scaledWidth = max(2, Int(fittedWidth / 2) * 2)
    let scaledHeight = max(2, Int(fittedHeight / 2) * 2)
    let x = max(0, Int((visibleWidth - Double(scaledWidth)) / 4) * 2)
    let y = max(0, (canvasHeight - scaledHeight) / 4 * 2)
    return "scale=\(scaledWidth):\(scaledHeight),setsar=1,pad=\(canvasWidth):\(canvasHeight):\(x):\(y):black"
}
#endif
