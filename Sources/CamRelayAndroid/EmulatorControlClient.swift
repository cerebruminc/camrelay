import CamRelayCore
import Foundation

struct EmulatorControlEndpoint: Equatable, Sendable {
    let port: UInt16
    let token: String
    let serial: String
}

struct EmulatorControlClient: Sendable {
    private let curlURL: URL

    init(curlURL: URL = URL(fileURLWithPath: "/usr/bin/curl")) {
        self.curlURL = curlURL
    }

    func setMedia(
        _ media: MediaFixture,
        alternatePath: Bool = false,
        endpoint: EmulatorControlEndpoint
    ) throws {
        try setSceneMode(androidSceneMode(for: media, alternatePath: alternatePath), endpoint: endpoint)
    }

    func setSceneMode(_ sceneMode: String, endpoint: EmulatorControlEndpoint) throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: curlURL.path) else {
            throw RelayError("curl is required to control Android Emulator but was not found at \(curlURL.path).")
        }

        let requestURL = fileManager.temporaryDirectory
            .appendingPathComponent("camrelay-android-request-\(UUID().uuidString)")
        try grpcEnvironmentRequest(sceneMode: sceneMode)
            .write(to: requestURL, options: [.atomic])
        defer { try? fileManager.removeItem(at: requestURL) }

        let headers = """
        content-type: application/grpc
        te: trailers
        authorization: Bearer \(endpoint.token)

        """

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = curlURL
        process.arguments = [
            "--http2-prior-knowledge",
            "--silent",
            "--show-error",
            "--connect-timeout", "2",
            "--max-time", "10",
            "--dump-header", "-",
            "--output", "/dev/null",
            "--header", "@-",
            "--data-binary", "@\(requestURL.path)",
            "http://127.0.0.1:\(endpoint.port)/android.emulation.control.EmulatorController/setEnvironment",
        ]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: Data(headers.utf8))
            try input.fileHandleForWriting.close()
        } catch {
            if process.isRunning { process.terminate() }
            throw RelayError("Could not contact Android Emulator control: \(error.localizedDescription)")
        }

        let headersData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RelayError("Android Emulator control failed: \(message.isEmpty ? "curl exited with status \(process.terminationStatus)." : message)")
        }

        let responseHeaders = String(decoding: headersData, as: UTF8.self)
        guard grpcStatus(in: responseHeaders) == 0 else {
            let status = grpcStatus(in: responseHeaders).map(String.init) ?? "missing"
            let message = grpcHeader(named: "grpc-message", in: responseHeaders)?
                .removingPercentEncoding ?? "no error message"
            throw RelayError("Android Emulator rejected the fixture (gRPC status \(status)): \(message)")
        }
    }
}

func androidSceneMode(for media: MediaFixture, alternatePath: Bool = false) -> String {
    let path: String
    if alternatePath {
        // The emulator ignores an unchanged scene mode. An equivalent path makes replay reload the file.
        let directory = media.url.deletingLastPathComponent().path
        let separator = directory == "/" ? "" : "/"
        path = "\(directory)\(separator)./\(media.url.lastPathComponent)"
    } else {
        path = media.url.path
    }
    return "\(media.kind == .image ? "imagefile" : "videofile"):\(path)"
}

func grpcEnvironmentRequest(sceneMode: String) -> Data {
    var entry = Data()
    appendLengthDelimited(field: 1, value: Data("scene.mode".utf8), to: &entry)
    appendLengthDelimited(field: 2, value: Data(sceneMode.utf8), to: &entry)

    var message = Data()
    appendLengthDelimited(field: 1, value: entry, to: &message)

    var request = Data([0])
    var length = UInt32(message.count).bigEndian
    request.append(withUnsafeBytes(of: &length) { Data($0) })
    request.append(message)
    return request
}

func grpcStatus(in headers: String) -> Int? {
    grpcHeader(named: "grpc-status", in: headers).flatMap(Int.init)
}

private func grpcHeader(named name: String, in headers: String) -> String? {
    let prefix = name.lowercased() + ":"
    return headers.split(whereSeparator: \Character.isNewline).reversed().compactMap { line -> String? in
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased().hasPrefix(prefix) else { return nil }
        return text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }.first
}

private func appendLengthDelimited(field: UInt64, value: Data, to data: inout Data) {
    appendVarint(field << 3 | 2, to: &data)
    appendVarint(UInt64(value.count), to: &data)
    data.append(value)
}

private func appendVarint(_ value: UInt64, to data: inout Data) {
    var remaining = value
    repeat {
        var byte = UInt8(remaining & 0x7f)
        remaining >>= 7
        if remaining != 0 { byte |= 0x80 }
        data.append(byte)
    } while remaining != 0
}
