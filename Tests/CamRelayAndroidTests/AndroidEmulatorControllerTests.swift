@testable import CamRelayAndroid
import CamRelayCore
import Foundation
import Testing

@Test("Finds the Android SDK and resolves an AVD directory")
func locatesSDKAndAVD() throws {
    let fixture = try AndroidSDKFixture()
    defer { fixture.remove() }
    let avdDirectory = try fixture.addAVD("Pixel_10")

    let sdk = try AndroidSDK(environment: fixture.environment)
    #expect(sdk.rootURL == fixture.sdkRoot.standardizedFileURL)
    #expect(try sdk.avdDirectory(named: "Pixel_10") == avdDirectory.standardizedFileURL)
}

@Test("Selects the only AVD or requires an explicit choice")
func selectsAndroidAVD() throws {
    let fixture = try AndroidSDKFixture()
    defer { fixture.remove() }
    _ = try fixture.addAVD("Pixel_10")
    let sdk = try AndroidSDK(environment: fixture.environment)

    let only = AndroidEmulatorController(
        sdk: sdk,
        environment: fixture.environment,
        listRunner: { Data("Pixel_10\n".utf8) }
    )
    #expect(try only.selectAVD(named: nil).id == "Pixel_10")

    let multiple = AndroidEmulatorController(
        sdk: sdk,
        environment: fixture.environment,
        listRunner: { Data("Tablet\nPixel_10\n".utf8) }
    )
    #expect(throws: AndroidEmulatorControllerError.multipleAVDs(["Pixel_10", "Tablet"])) {
        _ = try multiple.selectAVD(named: nil)
    }
    #expect(throws: AndroidEmulatorControllerError.unknownAVD("Missing", available: ["Pixel_10", "Tablet"])) {
        _ = try multiple.selectAVD(named: "Missing")
    }
}

@Test("Parses private emulator discovery without weakening authentication")
func parsesEmulatorDiscovery() {
    let endpoint = emulatorEndpoint(from: """
    avd.id=Pixel_10
    port.serial=5554
    grpc.port=55424
    grpc.token=private-token
    """)
    #expect(endpoint == EmulatorControlEndpoint(port: 55424, token: "private-token", serial: "emulator-5554"))
    #expect(emulatorEndpoint(from: "grpc.port=55424\nport.serial=5554\n") == nil)
}

@Test("Encodes setEnvironment as a framed gRPC protobuf")
func encodesEnvironmentRequest() {
    let request = grpcEnvironmentRequest(sceneMode: "imagefile:/x")
    let expected = Data([0, 0, 0, 0, 28, 10, 26, 10, 10])
        + Data("scene.mode".utf8)
        + Data([18, 12])
        + Data("imagefile:/x".utf8)
    #expect(request == expected)
    #expect(grpcStatus(in: "HTTP/2 200\r\ngrpc-status: 0\r\n") == 0)
    #expect(grpcStatus(in: "HTTP/2 200\r\n") == nil)
}

@Test("Maps image and video fixtures to Android environment modes")
func mapsAndroidSceneModes() throws {
    let fixture = try AndroidMediaFixture()
    defer { fixture.remove() }

    #expect(androidSceneMode(for: try MediaFixture(path: fixture.imageURL.path))
        == "imagefile:\(fixture.imageURL.path)")
    #expect(androidSceneMode(for: try MediaFixture(path: fixture.videoURL.path))
        == "videofile:\(fixture.videoURL.path)")
    #expect(androidSceneMode(for: try MediaFixture(path: fixture.videoURL.path), alternatePath: true)
        == "videofile:\(fixture.root.path)/./colors.mp4")
}

@Test("Switches and replays Android fixtures without restarting the session")
func controlsAndroidPlayback() throws {
    let fixture = try AndroidMediaFixture()
    defer { fixture.remove() }
    let recorder = MediaRecorder()
    let playback = try makePlayback(fixture: fixture) { recorder.append($0, alternatePath: $1) }

    #expect(playback.snapshot() == AndroidPlaybackSnapshot(
        fixtures: ["pattern", "colors"], selected: "pattern", generation: 1
    ))
    #expect(try playback.apply(RelayControlRequest(action: .select, fixture: "colors")) == 2)
    #expect(try playback.apply(RelayControlRequest(action: .replay)) == 3)
    #expect(try playback.apply(RelayControlRequest(action: .next)) == 4)
    #expect(try playback.apply(RelayControlRequest(action: .previous)) == 5)
    #expect(playback.snapshot().selected == "colors")
    #expect(recorder.paths == [
        fixture.videoURL.path,
        fixture.videoURL.path,
        fixture.imageURL.path,
        fixture.videoURL.path,
    ])
    #expect(recorder.alternatePaths == [false, true, false, true])
}

@Test("Keeps the active Android fixture when replacement fails")
func preservesAndroidPlaybackAfterFailure() throws {
    let fixture = try AndroidMediaFixture()
    defer { fixture.remove() }
    let playback = try makePlayback(fixture: fixture) { media, _ in
        if media.kind == .video { throw RelayError("rejected") }
    }

    #expect(throws: RelayError.self) {
        _ = try playback.apply(RelayControlRequest(action: .select, fixture: "colors"))
    }
    #expect(playback.snapshot() == AndroidPlaybackSnapshot(
        fixtures: ["pattern", "colors"], selected: "pattern", generation: 1
    ))
}

@Test("Rejects Android pause and delivery acknowledgement controls")
func rejectsUnsupportedAndroidControls() throws {
    let fixture = try AndroidMediaFixture()
    defer { fixture.remove() }
    let playback = try makePlayback(fixture: fixture) { _, _ in }

    #expect(throws: RelayError.self) {
        _ = try playback.apply(RelayControlRequest(action: .pause))
    }
    #expect(throws: RelayError.self) {
        _ = try playback.apply(RelayControlRequest(action: .replay, waitForFrame: true))
    }
}

@Test("Restores an AVD environment file after the relay")
func restoresAVDEnvironment() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("camrelay-android-environment-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let environmentURL = root.appendingPathComponent("environment.ini")
    let original = Data("scene.mode = none\n".utf8)
    try original.write(to: environmentURL)
    let imageURL = root.appendingPathComponent("fixture with spaces.png")
    try Data().write(to: imageURL)

    let managed = try AVDEnvironmentFile(avdDirectory: root, media: try MediaFixture(path: imageURL.path))
    #expect(String(decoding: try Data(contentsOf: environmentURL), as: UTF8.self)
        == "scene.mode = imagefile:\(imageURL.path)\n")
    try managed.restore()
    #expect(try Data(contentsOf: environmentURL) == original)
}

@Test("Removes a newly created AVD environment file after the relay")
func removesCreatedAVDEnvironment() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("camrelay-android-new-environment-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let environmentURL = root.appendingPathComponent("environment.ini")
    let imageURL = root.appendingPathComponent("fixture.png")
    try Data().write(to: imageURL)

    let managed = try AVDEnvironmentFile(avdDirectory: root, media: try MediaFixture(path: imageURL.path))
    #expect(FileManager.default.fileExists(atPath: environmentURL.path))
    try managed.restore()
    #expect(!FileManager.default.fileExists(atPath: environmentURL.path))
}

private final class AndroidSDKFixture {
    let root: URL
    let sdkRoot: URL
    let avdHome: URL
    let environment: [String: String]

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camrelay-android-sdk-test-\(UUID().uuidString)")
        sdkRoot = root.appendingPathComponent("sdk")
        avdHome = root.appendingPathComponent("avd")
        try FileManager.default.createDirectory(
            at: sdkRoot.appendingPathComponent("emulator"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sdkRoot.appendingPathComponent("platform-tools"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: avdHome, withIntermediateDirectories: true)
        for executable in [
            sdkRoot.appendingPathComponent("emulator/emulator"),
            sdkRoot.appendingPathComponent("platform-tools/adb"),
        ] {
            try Data().write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        environment = [
            "ANDROID_SDK_ROOT": sdkRoot.path,
            "ANDROID_AVD_HOME": avdHome.path,
            "HOME": root.path,
        ]
    }

    func addAVD(_ name: String) throws -> URL {
        let directory = root.appendingPathComponent("devices/\(name).avd")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("path=\(directory.path)\n".utf8)
            .write(to: avdHome.appendingPathComponent("\(name).ini"))
        return directory
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class AndroidMediaFixture {
    let root: URL
    let imageURL: URL
    let videoURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camrelay-android-media-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        imageURL = root.appendingPathComponent("pattern.png")
        videoURL = root.appendingPathComponent("colors.mp4")
        try Data().write(to: imageURL)
        try Data().write(to: videoURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class MediaRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    private var alternateStorage: [Bool] = []

    var paths: [String] { lock.withLock { storage } }
    var alternatePaths: [Bool] { lock.withLock { alternateStorage } }

    func append(_ media: MediaFixture, alternatePath: Bool) {
        lock.withLock {
            storage.append(media.url.path)
            alternateStorage.append(alternatePath)
        }
    }
}

private func makePlayback(
    fixture: AndroidMediaFixture,
    setMedia: @escaping @Sendable (MediaFixture, Bool) throws -> Void
) throws -> AndroidPlaybackController {
    AndroidPlaybackController(
        fixtures: [
            AndroidFixture(name: "pattern", media: try MediaFixture(path: fixture.imageURL.path)),
            AndroidFixture(name: "colors", media: try MediaFixture(path: fixture.videoURL.path)),
        ],
        initial: "pattern",
        setMedia: setMedia
    )
}
