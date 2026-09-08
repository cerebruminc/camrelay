import CamRelayCore
import Foundation

public final class AndroidRelaySession: @unchecked Sendable {
    public let device: AndroidVirtualDevice
    public let serial: String

    private let emulator: AndroidEmulatorProcess
    private let environmentFile: AVDEnvironmentFile
    private let avdLease: RelayLease
    private let sessionName: String
    private let fixture: NamedFixture
    private let cleanupLock = NSLock()
    private var cleanedUp = false
    private var stopStarted = false

    init(
        device: AndroidVirtualDevice,
        serial: String,
        emulator: AndroidEmulatorProcess,
        environmentFile: AVDEnvironmentFile,
        avdLease: RelayLease,
        sessionName: String,
        fixture: NamedFixture
    ) {
        self.device = device
        self.serial = serial
        self.emulator = emulator
        self.environmentFile = environmentFile
        self.avdLease = avdLease
        self.sessionName = sessionName
        self.fixture = fixture
    }

    public func stop() {
        do { try stopChecked() }
        catch {
            FileHandle.standardError.write(Data(
                "camrelay: could not clean up Android AVD \(device.id): \(error.localizedDescription)\n".utf8
            ))
        }
    }

    public func waitUntilExit() {
        emulator.waitUntilExit()
    }

    public var stopWasRequested: Bool {
        cleanupLock.withLock { stopStarted }
    }

    public func status() -> RelayStatus {
        RelayStatus(
            session: sessionName,
            simulator: device.id,
            simulatorID: serial,
            fixtures: [fixture.name],
            selected: fixture.name,
            paused: false,
            generation: 1,
            positionSeconds: 0,
            connectedReceivers: 0,
            acknowledgedReceivers: 0,
            width: 0,
            height: 0,
            framesPerSecond: 0,
            error: nil
        )
    }

    public func handle(_ request: RelayControlRequest) async -> RelayControlResponse {
        do {
            try request.validate()
            switch request.action {
            case .status:
                break
            case .stop:
                try await Task.detached(priority: .userInitiated) { try self.stopChecked() }.value
            default:
                throw RelayError("Android Phase 1 supports one image fixture plus status and stop. Live controls arrive in Phase 2.")
            }
            return RelayControlResponse(status: status())
        } catch {
            return RelayControlResponse(status: status(), error: error.localizedDescription)
        }
    }

    private func stopChecked() throws {
        cleanupLock.lock()
        defer { cleanupLock.unlock() }
        guard !cleanedUp else { return }
        stopStarted = true
        emulator.stop()
        try environmentFile.restore()
        cleanedUp = true
    }
}

public struct AndroidRelay {
    private let controller: AndroidEmulatorController
    private let controlClient: EmulatorControlClient

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let sdk = try AndroidSDK(environment: environment)
        controller = AndroidEmulatorController(sdk: sdk, environment: environment)
        controlClient = EmulatorControlClient()
    }

    public func start(options: RelayRunOptions) throws -> AndroidRelaySession {
        guard options.platform == .android else { throw RelayError("Expected Android run options.") }
        guard options.fixtures.count == 1 else {
            throw RelayError("Android Phase 1 accepts exactly one image fixture.")
        }
        guard !options.paused else {
            throw RelayError("Android pause support arrives in Phase 2.")
        }

        let namedFixture = options.fixtures[0]
        let media = try MediaFixture(path: namedFixture.path)
        guard media.kind == .image else {
            throw RelayError("Android Phase 1 accepts an image fixture. Video support arrives in Phase 2.")
        }

        let device = try controller.selectAVD(named: options.androidAVD)
        try RelayCommand.validateName(device.id, kind: "AVD name")
        let lease = try RelayLease(key: "android-\(device.id)")
        let environmentFile = try AVDEnvironmentFile(avdDirectory: device.directoryURL, imageURL: media.url)
        var emulator: AndroidEmulatorProcess?

        do {
            let launched = try controller.launch(device)
            emulator = launched
            let endpoint = try launched.waitForControl()
            try controlClient.setImage(media.url, endpoint: endpoint)
            try launched.waitUntilBooted(endpoint: endpoint)
            return AndroidRelaySession(
                device: device,
                serial: endpoint.serial,
                emulator: launched,
                environmentFile: environmentFile,
                avdLease: lease,
                sessionName: options.session,
                fixture: NamedFixture(name: namedFixture.name, path: media.url.path)
            )
        } catch {
            let startupError = error
            emulator?.stop()
            do { try environmentFile.restore() }
            catch {
                throw RelayError("\(startupError.localizedDescription) Cleanup also failed: \(error.localizedDescription)")
            }
            throw startupError
        }
    }
}
