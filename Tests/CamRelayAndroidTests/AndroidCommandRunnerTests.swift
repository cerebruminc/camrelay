#if os(Linux)
@testable import CamRelayAndroid
import CamRelayCore
import Foundation
import Glibc
import Testing

@Test("Finishes an Android command while its background daemon remains running")
func androidCommandDoesNotWaitForDaemon() throws {
    let fixture = try AndroidCommandFixture()
    defer { fixture.remove() }
    let daemonPID = fixture.directory.appendingPathComponent("daemon.pid")
    let finished = fixture.directory.appendingPathComponent("daemon.finished")
    try fixture.write("""
    #!/bin/sh
    (/bin/sleep 2; printf finished > "$HOME/daemon.finished") </dev/null >/dev/null 2>&1 &
    printf '%s\\n' "$!" > "$HOME/daemon.pid"
    printf '1\\n'
    """)
    defer {
        if let text = try? String(contentsOf: daemonPID, encoding: .utf8),
           let processIdentifier = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(processIdentifier, SIGTERM)
        }
    }

    let output = try runAndroidCommand(fixture.executable, arguments: [], environment: fixture.environment)

    #expect(String(decoding: output, as: UTF8.self) == "1\n")
    #expect(!FileManager.default.fileExists(atPath: finished.path))
}

@Test("Drains large Android diagnostics without blocking stdout")
func androidCommandHandlesLargeDiagnostics() throws {
    let fixture = try AndroidCommandFixture()
    defer { fixture.remove() }
    try fixture.write("""
    #!/bin/sh
    i=0
    while [ "$i" -lt 10000 ]; do
      printf 'Android diagnostic output before stdout\\n' >&2
      i=$((i + 1))
    done
    printf 'ready\\n'
    """)

    let output = try runAndroidCommand(fixture.executable, arguments: [], environment: fixture.environment)

    #expect(String(decoding: output, as: UTF8.self) == "ready\n")
}

@Test("Preserves Android arguments, environment, and command failure diagnostics")
func androidCommandPreservesInvocation() throws {
    let fixture = try AndroidCommandFixture()
    defer { fixture.remove() }
    try fixture.write("""
    #!/bin/sh
    printf '%s|%s\\n' "$1" "$CAMRELAY_COMMAND_TEST"
    """)
    var environment = fixture.environment
    environment["CAMRELAY_COMMAND_TEST"] = "value with spaces"
    let output = try runAndroidCommand(fixture.executable, arguments: ["argument with spaces"], environment: environment)
    #expect(String(decoding: output, as: UTF8.self) == "argument with spaces|value with spaces\n")

    try fixture.write("#!/bin/sh\nprintf 'ADB rejected the device\\n' >&2\nexit 7\n")
    #expect(throws: RelayError("command failed: ADB rejected the device")) {
        _ = try runAndroidCommand(fixture.executable, arguments: [], environment: environment)
    }
}

private struct AndroidCommandFixture {
    let directory: URL
    let executable: URL
    var environment: [String: String] { ["HOME": directory.path] }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("camrelay-android-command-test-\(UUID().uuidString)")
        executable = directory.appendingPathComponent("command")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ script: String) throws {
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
#endif
