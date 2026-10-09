#if os(Linux)
import CamRelayCore
import Foundation
import Glibc

func runLinuxAndroidCommand(
    _ executableURL: URL,
    arguments: [String],
    environment: [String: String]
) throws -> Data {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("camrelay-android-command-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let outputURL = directory.appendingPathComponent("stdout")
    let errorURL = directory.appendingPathComponent("stderr")
    for url in [outputURL, errorURL] {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw RelayError("Could not capture \(executableURL.lastPathComponent) output.")
        }
    }
    let output = try FileHandle(forWritingTo: outputURL)
    defer { try? output.close() }
    let errors = try FileHandle(forWritingTo: errorURL)
    defer { try? errors.close() }

    var actions = posix_spawn_file_actions_t()
    try checkAndroidSpawn(posix_spawn_file_actions_init(&actions), executableURL)
    defer { posix_spawn_file_actions_destroy(&actions) }
    try checkAndroidSpawn(posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDOUT_FILENO), executableURL)
    try checkAndroidSpawn(posix_spawn_file_actions_adddup2(&actions, errors.fileDescriptor, STDERR_FILENO), executableURL)
    // ADB can fork a persistent server. Do not pass parent control descriptors to it.
    for name in try FileManager.default.contentsOfDirectory(atPath: "/proc/self/fd") {
        if let descriptor = Int32(name), descriptor > STDERR_FILENO {
            try checkAndroidSpawn(posix_spawn_file_actions_addclose(&actions, descriptor), executableURL)
        }
    }

    let argv = ([executableURL.path] + arguments).map { strdup($0) } + [nil]
    let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
        for pointer in argv + envp { free(pointer) }
    }
    var processIdentifier: pid_t = 0
    let spawned = argv.withUnsafeBufferPointer { argv in
        envp.withUnsafeBufferPointer { envp in
            posix_spawn(&processIdentifier, executableURL.path, &actions, nil, argv.baseAddress!, envp.baseAddress!)
        }
    }
    try checkAndroidSpawn(spawned, executableURL)

    // Foundation Process on Linux monitors an inherited socket. A daemon can keep
    // that socket open after its parent exits; waitpid observes this child directly.
    var status: Int32 = 0
    var waited: pid_t
    repeat { waited = waitpid(processIdentifier, &status, 0) } while waited == -1 && errno == EINTR
    guard waited == processIdentifier else {
        throw RelayError("Could not wait for \(executableURL.lastPathComponent): \(String(cString: strerror(errno)))")
    }
    guard status == 0 else {
        let message = String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = status & 0x7f == 0 ? "exit status \((status >> 8) & 0xff)" : "signal \(status & 0x7f)"
        throw RelayError("\(executableURL.lastPathComponent) failed: \(message.isEmpty ? reason : message)")
    }
    return try Data(contentsOf: outputURL)
}

private func checkAndroidSpawn(_ result: Int32, _ executableURL: URL) throws {
    guard result == 0 else {
        throw RelayError("Could not launch \(executableURL.lastPathComponent): \(String(cString: strerror(result)))")
    }
}
#endif
