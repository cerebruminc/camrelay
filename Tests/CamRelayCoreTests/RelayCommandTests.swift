import CamRelayCore
import Testing

@Test("Legacy media command keeps its simple invocation")
func parsesLegacyCommand() throws {
    guard case .run(let options) = try RelayCommand.parse(["a video.mp4"]) else {
        Issue.record("Expected run command")
        return
    }
    #expect(options.session == "default")
    #expect(options.platform == .iOS)
    #expect(options.fixtures == [NamedFixture(name: "fixture-1", path: "a video.mp4")])
    #expect(!options.noInteractive)
}

@Test("Parses an Android image command and optional AVD")
func parsesAndroidCommand() throws {
    guard case .run(let options) = try RelayCommand.parse([
        "--platform", "android", "--avd", "Pixel_10", "camera.png",
    ]) else { Issue.record("Expected run command"); return }
    #expect(options.platform == .android)
    #expect(options.androidAVD == "Pixel_10")
    #expect(options.fixtures == [NamedFixture(name: "fixture-1", path: "camera.png")])
}

@Test("Parses named fixtures, initial selection, and headless playback")
func parsesNamedFixtures() throws {
    guard case .run(let options) = try RelayCommand.parse([
        "run", "--session", "demo", "--fixture", "colors=/a=b.mp4",
        "--fixture", "pattern=checkerboard.png", "--initial", "pattern", "--paused", "--no-interactive",
    ]) else { Issue.record("Expected run command"); return }
    #expect(options.fixtures[0].path == "/a=b.mp4")
    #expect(options.initial == "pattern")
    #expect(options.paused && options.noInteractive)
}

@Test("Control commands carry bounded delivery waits")
func parsesControl() throws {
    let command = try RelayCommand.parse([
        "select", "pattern", "--session", "demo", "--paused",
        "--wait-for-frame", "--timeout", "2.5s", "--json",
    ])
    #expect(command == .control(
        session: "demo",
        request: RelayControlRequest(action: .select, fixture: "pattern", paused: true, waitForFrame: true, timeout: 2.5),
        json: true, waitForReady: false
    ))
}

@Test("Rejects malformed and ambiguous command input", arguments: [
    [], ["run"], ["run", "--session"], ["run", "--session", "../escape", "a.mp4"],
    ["run", "--fixture", "same=a.mp4", "--fixture", "same=b.mp4"],
    ["run", "--fixture", "=a.mp4"], ["run", "--fixture", "colors="],
    ["run", "a.mp4", "--initial", "unknown"], ["select"], ["select", "a", "b"],
    ["status", "--wait-for-frame"], ["stop", "--paused"], ["wait", "--timeout", "0"],
    ["select", "a", "--timeout", "nan"], ["select", "a", "--timeout", "301s"],
    ["run", "--unknown"], ["run", "--avd", "Pixel_10", "a.png"],
    ["--platform", "android", "--avd", "../escape", "a.png"],
    ["--platform", "windows", "a.png"],
])
func rejectsBadCommands(arguments: [String]) {
    #expect(throws: RelayError.self) { try RelayCommand.parse(arguments) }
}

@Test("Readiness waiting is distinct from status")
func parsesWait() throws {
    #expect(try RelayCommand.parse(["wait", "--timeout", "3"]) == .control(
        session: "default", request: RelayControlRequest(action: .status, timeout: 3),
        json: false, waitForReady: true
    ))
}

@Test("Double dash allows a positional path starting with a hyphen")
func parsesDoubleDash() throws {
    guard case .run(let options) = try RelayCommand.parse(["run", "--", "-fixture.mp4"]) else {
        Issue.record("Expected run command"); return
    }
    #expect(options.fixtures.first?.path == "-fixture.mp4")
}
