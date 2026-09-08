@testable import CamRelayAndroid
import CamRelayCore
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
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
    #expect(emulatorEndpoint(from: "grpc.port=55424\ngrpc.token=private-token\nport.serial=5554\n") == nil)
}

@Test("Attaches to a running AVD through its private discovery file")
func discoversRunningAndroidAVD() throws {
    let fixture = try AndroidSDKFixture()
    defer { fixture.remove() }
    let avdDirectory = try fixture.addAVD("Test_AVD")
    let runningDirectory = fixture.root
        .appendingPathComponent("Library/Caches/TemporaryItems/avd/running")
    try FileManager.default.createDirectory(at: runningDirectory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runningDirectory.path)
    let discoveryURL = runningDirectory.appendingPathComponent("pid_\(getpid()).ini")
    try Data("""
    avd.id=Test_AVD
    port.serial=5554
    grpc.port=55424
    grpc.token=private-token
    """.utf8).write(to: discoveryURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: discoveryURL.path)

    let controller = AndroidEmulatorController(
        sdk: try AndroidSDK(environment: fixture.environment),
        environment: fixture.environment,
        listRunner: { Data("Test_AVD\n".utf8) }
    )
    let connection = try controller.runningConnection(for: AndroidVirtualDevice(
        id: "Test_AVD", directoryURL: avdDirectory
    ))
    #expect(connection.endpoint == EmulatorControlEndpoint(
        port: 55424, token: "private-token", serial: "emulator-5554"
    ))
    #expect(connection.processIdentifier == getpid())
}

@Test("Counts app-visible Android camera mappings")
func countsMappedAndroidCameras() {
    #expect(mappedCameraDeviceCount(in: """
      Device 0 maps to "10"
      Device 1 maps to "11"
      Device 10 is closed, no client instance
    """) == 2)
    #expect(mappedCameraDeviceCount(in: "Device 0 maps to \"10\"") == 1)
    #expect(mappedCameraDeviceCount(in: "Device 10 is closed") == 0)
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

@Test("Stops Android playback before restoring the idle scene")
func stopsAndroidPlayback() throws {
    let fixture = try AndroidMediaFixture()
    defer { fixture.remove() }
    let playback = try makePlayback(fixture: fixture) { _, _ in }
    var restored = false

    try playback.stop { restored = true }

    #expect(restored)
    #expect(throws: RelayError.self) {
        _ = try playback.apply(RelayControlRequest(action: .replay))
    }
}

@Test("Reads the AVD idle scene without changing its environment file")
func readsAVDEnvironment() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("camrelay-android-environment-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let environmentURL = root.appendingPathComponent("environment.ini")
    let original = Data("scene.mode = imagefile:/existing/image.png\n".utf8)
    try original.write(to: environmentURL)

    let environment = try AVDEnvironmentFile(avdDirectory: root)
    #expect(environment.sceneMode == "imagefile:/existing/image.png")
    #expect(try Data(contentsOf: environmentURL) == original)
}

@Test("Uses an empty idle scene without creating an AVD environment file")
func defaultsMissingAVDEnvironment() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("camrelay-android-new-environment-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let environmentURL = root.appendingPathComponent("environment.ini")

    let environment = try AVDEnvironmentFile(avdDirectory: root)
    #expect(environment.sceneMode == "none")
    #expect(!FileManager.default.fileExists(atPath: environmentURL.path))
}

@Test("Prepares the complete image inside the Android environment camera window")
func preparesAndroidImageForFullFrame() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("camrelay-android-image-preparation-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("red.png")
    try writeSolidPNG(to: source, width: 160, height: 120)

    let preparer = try AndroidMediaPreparer()
    let prepared = try preparer.prepare(MediaFixture(path: source.path))
    #expect(prepared.url != source)
    #expect(prepared.kind == .image)
    #expect(try preparer.prepare(MediaFixture(path: source.path)) == prepared)

    guard let image = CIImage(contentsOf: prepared.url) else {
        Issue.record("Could not read prepared image")
        return
    }
    #expect(image.extent.size == CGSize(width: 160, height: 120))
    let red = pixel(at: CGPoint(x: 20, y: 60), in: image)
    #expect(red[0] > 240 && red[1] < 50 && red[2] < 20 && red[3] == 255)
    #expect(pixel(at: CGPoint(x: 150, y: 60), in: image) == [0, 0, 0, 255])
    #expect(pixel(at: CGPoint(x: 20, y: 30), in: image) == [0, 0, 0, 255])
    #expect(pixel(at: CGPoint(x: 20, y: 5), in: image) == [0, 0, 0, 255])

    let preparedPath = prepared.url.path
    preparer.cleanup()
    #expect(!FileManager.default.fileExists(atPath: preparedPath))
}

@Test("Defines the fixed Android environment camera window")
func calculatesAndroidEnvironmentCameraWindow() {
    #expect(androidEnvironmentVisibleRect(in: CGRect(x: 0, y: 0, width: 160, height: 120))
        == CGRect(x: 0, y: 26.25, width: 90, height: 67.5))
    #expect(androidFittedContentRect(
        sourceAspectRatio: 9.0 / 16.0,
        in: CGRect(x: 0, y: 0, width: 90, height: 120)
    ) == CGRect(x: 11.25, y: 0, width: 67.5, height: 120))
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

private func writeSolidPNG(to url: URL, width: Int, height: Int) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw RelayError("Could not create test image context.")
    }
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw RelayError("Could not create test PNG.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw RelayError("Could not write test PNG.") }
}

private func pixel(at point: CGPoint, in image: CIImage) -> [UInt8] {
    let context = CIContext(options: [.cacheIntermediates: false])
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var value = [UInt8](repeating: 0, count: 4)
    value.withUnsafeMutableBytes { bytes in
        context.render(
            image, toBitmap: bytes.baseAddress!, rowBytes: 4,
            bounds: CGRect(origin: point, size: CGSize(width: 1, height: 1)),
            format: .RGBA8, colorSpace: colorSpace
        )
    }
    return value
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
