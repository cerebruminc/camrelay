#if os(macOS)
@testable import CamRelayIOS
import Foundation
import Testing

@Test("Finds the packaged runtime from a different working directory")
func findsPackagedRuntime() throws {
    let fixture = try RuntimeLocationFixture()
    defer { fixture.remove() }
    let runtime = try fixture.addRuntime("package/runtime/CamRelayRuntime.dylib")

    let found = try fixture.locator().runtimeURL()

    #expect(found == runtime)
}

@Test("Finds the packaged runtime through an executable symlink")
func findsPackagedRuntimeThroughSymlink() throws {
    let fixture = try RuntimeLocationFixture()
    defer { fixture.remove() }
    let runtime = try fixture.addRuntime("package/runtime/CamRelayRuntime.dylib")
    let link = fixture.root.appendingPathComponent("camrelay-link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.executable)

    #expect(try fixture.locator(executable: link).runtimeURL() == runtime)
}

@Test("Preserves runtime overrides and source-build discovery")
func preservesRuntimeOverrideAndSourceDiscovery() throws {
    let fixture = try RuntimeLocationFixture()
    defer { fixture.remove() }
    let source = try fixture.addRuntime("working/.build/runtime/CamRelayRuntime.dylib")
    _ = try fixture.addRuntime("package/runtime/CamRelayRuntime.dylib")
    let override = try fixture.addRuntime("override/CamRelayRuntime.dylib")

    #expect(try fixture.locator().runtimeURL() == source)
    #expect(try fixture.locator(environment: ["CAMRELAY_RUNTIME_PATH": override.path]).runtimeURL() == override)
}

@Test("Reports a missing packaged runtime")
func reportsMissingPackagedRuntime() throws {
    let fixture = try RuntimeLocationFixture()
    defer { fixture.remove() }

    #expect(throws: IOSRelayError.self) {
        _ = try fixture.locator().runtimeURL()
    }
}

private final class RuntimeLocationFixture {
    let root: URL
    let executable: URL
    let workingDirectory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camrelay-runtime-location-\(UUID().uuidString)").resolvingSymlinksInPath()
        executable = root.appendingPathComponent("package/bin/camrelay")
        workingDirectory = root.appendingPathComponent("working")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try Data().write(to: executable)
    }

    func addRuntime(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
        return url
    }

    func locator(environment: [String: String] = [:], executable: URL? = nil) -> RuntimeLocator {
        RuntimeLocator(environment: environment, executableURL: executable ?? self.executable,
                       workingDirectoryURL: workingDirectory)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
#endif
