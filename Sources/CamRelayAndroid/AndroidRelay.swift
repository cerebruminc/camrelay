import CamRelayCore
import Foundation

public final class AndroidRelaySession: @unchecked Sendable {
    public let device: AndroidVirtualDevice
    public let serial: String

    private let emulator: AndroidEmulatorConnection
    private let idleSceneMode: String
    private let controlClient: EmulatorControlClient
    private let avdLease: RelayLease
    private let sessionName: String
    private let playback: AndroidPlaybackController
    private let mediaPreparer: AndroidMediaPreparer
    private let cleanupLock = NSLock()
    private var cleanedUp = false
    private var stopStarted = false

    init(
        device: AndroidVirtualDevice,
        serial: String,
        emulator: AndroidEmulatorConnection,
        idleSceneMode: String,
        controlClient: EmulatorControlClient,
        avdLease: RelayLease,
        sessionName: String,
        playback: AndroidPlaybackController,
        mediaPreparer: AndroidMediaPreparer
    ) {
        self.device = device
        self.serial = serial
        self.emulator = emulator
        self.idleSceneMode = idleSceneMode
        self.controlClient = controlClient
        self.avdLease = avdLease
        self.sessionName = sessionName
        self.playback = playback
        self.mediaPreparer = mediaPreparer
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
        let playback = playback.snapshot()
        return RelayStatus(
            session: sessionName,
            simulator: device.id,
            simulatorID: serial,
            fixtures: playback.fixtures,
            selected: playback.selected,
            paused: false,
            generation: playback.generation,
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
                _ = try await Task.detached(priority: .userInitiated) {
                    try self.playback.apply(request)
                }.value
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
        var resetError: Error?
        do {
            try playback.stop {
                if emulator.isRunning {
                    try controlClient.setSceneMode(idleSceneMode, endpoint: emulator.endpoint)
                }
            }
        } catch {
            if emulator.isRunning { resetError = error }
        }
        cleanedUp = true
        if let resetError {
            let directory = mediaPreparer.leaveFilesInPlace()
            throw RelayError("\(resetError.localizedDescription) Temporary media remains at \(directory.path).")
        }
        mediaPreparer.cleanup()
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
        guard !options.fixtures.isEmpty else { throw RelayError("Provide at least one fixture.") }
        guard !options.paused else {
            throw RelayError("Android does not support starting paused yet.")
        }

        let fixtures = try options.fixtures.map { named in
            AndroidFixture(name: named.name, media: try MediaFixture(path: named.path))
        }
        let initialName = options.initial ?? fixtures[0].name
        guard let initial = fixtures.first(where: { $0.name == initialName }) else {
            throw RelayError("Unknown initial fixture: \(initialName)")
        }

        let device = try controller.selectAVD(named: options.androidAVD)
        try RelayCommand.validateName(device.id, kind: "AVD name")
        let lease = try RelayLease(key: "android-\(device.id)")
        let emulator: AndroidEmulatorConnection
        do { emulator = try controller.runningConnection(for: device) }
        catch AndroidEmulatorControllerError.notRunning {
            throw RelayError("Android AVD \(device.id) is not running with CamRelay camera support. Start it with `camrelay emulator start --platform android --avd \(device.id)`.")
        }
        try emulator.waitUntilBooted()
        try emulator.waitUntilEnvironmentCamerasAvailable()
        let environmentFile = try AVDEnvironmentFile(avdDirectory: device.directoryURL)
        let mediaPreparer = try AndroidMediaPreparer()
        let preparedInitial: MediaFixture
        do { preparedInitial = try mediaPreparer.prepare(initial.media) }
        catch {
            mediaPreparer.cleanup()
            throw error
        }

        do {
            try controlClient.setMedia(preparedInitial, alternatePath: true, endpoint: emulator.endpoint)
            let client = controlClient
            let playback = AndroidPlaybackController(fixtures: fixtures, initial: initial.name) { media, alternatePath in
                let prepared = try mediaPreparer.prepare(media)
                try client.setMedia(prepared, alternatePath: alternatePath, endpoint: emulator.endpoint)
            }
            return AndroidRelaySession(
                device: device,
                serial: emulator.endpoint.serial,
                emulator: emulator,
                idleSceneMode: environmentFile.sceneMode,
                controlClient: controlClient,
                avdLease: lease,
                sessionName: options.session,
                playback: playback,
                mediaPreparer: mediaPreparer
            )
        } catch {
            let startupError = error
            do {
                if emulator.isRunning {
                    try controlClient.setSceneMode(environmentFile.sceneMode, endpoint: emulator.endpoint)
                }
            }
            catch {
                let directory = mediaPreparer.leaveFilesInPlace()
                throw RelayError("\(startupError.localizedDescription) Cleanup also failed: \(error.localizedDescription) Temporary media remains at \(directory.path).")
            }
            mediaPreparer.cleanup()
            throw startupError
        }
    }
}

struct AndroidFixture: Equatable, Sendable {
    let name: String
    let media: MediaFixture
}

struct AndroidPlaybackSnapshot: Equatable, Sendable {
    let fixtures: [String]
    let selected: String
    let generation: UInt64
}

final class AndroidPlaybackController: @unchecked Sendable {
    private struct State {
        var selectedIndex: Int
        var generation: UInt64 = 1
        var alternatePath = true
    }

    private let fixtures: [AndroidFixture]
    private let setMedia: @Sendable (MediaFixture, Bool) throws -> Void
    private let commandLock = NSLock()
    private let stateLock = NSLock()
    private var state: State
    private var stopped = false

    init(
        fixtures: [AndroidFixture],
        initial: String,
        setMedia: @escaping @Sendable (MediaFixture, Bool) throws -> Void
    ) {
        self.fixtures = fixtures
        self.setMedia = setMedia
        state = State(selectedIndex: fixtures.firstIndex(where: { $0.name == initial }) ?? 0)
    }

    func snapshot() -> AndroidPlaybackSnapshot {
        stateLock.withLock {
            let selected = fixtures[state.selectedIndex]
            return AndroidPlaybackSnapshot(
                fixtures: fixtures.map(\.name),
                selected: selected.name,
                generation: state.generation
            )
        }
    }

    func apply(_ request: RelayControlRequest) throws -> UInt64 {
        commandLock.lock()
        defer { commandLock.unlock() }
        guard !stopped else { throw RelayError("Android relay has stopped.") }
        guard !request.paused else { throw RelayError("Android pause support is not available yet.") }
        guard !request.waitForFrame else {
            throw RelayError("Android does not provide app delivery acknowledgements for --wait-for-frame yet.")
        }

        let current = stateLock.withLock { state }
        let targetIndex: Int
        switch request.action {
        case .select:
            guard let name = request.fixture,
                  let index = fixtures.firstIndex(where: { $0.name == name }) else {
                throw RelayError("Unknown fixture: \(request.fixture ?? ""). Available: \(fixtures.map(\.name).joined(separator: ", "))")
            }
            targetIndex = index
        case .replay:
            targetIndex = current.selectedIndex
        case .next:
            targetIndex = (current.selectedIndex + 1) % fixtures.count
        case .previous:
            targetIndex = (current.selectedIndex + fixtures.count - 1) % fixtures.count
        case .pause, .play:
            throw RelayError("Android pause and play support is not available yet.")
        case .status, .stop:
            throw RelayError("This command does not change Android playback.")
        }

        let target = fixtures[targetIndex]
        let refreshed: MediaFixture
        do { refreshed = try MediaFixture(path: target.media.url.path) }
        catch {
            throw RelayError("Could not load fixture \(target.name) (\(target.media.url.path)): \(error.localizedDescription)")
        }
        let alternatePath = !current.alternatePath
        do { try setMedia(refreshed, alternatePath) }
        catch {
            throw RelayError("Could not select fixture \(target.name) (\(target.media.url.path)): \(error.localizedDescription)")
        }

        return stateLock.withLock {
            state.selectedIndex = targetIndex
            state.generation += 1
            state.alternatePath = alternatePath
            return state.generation
        }
    }

    func stop(reset: () throws -> Void) throws {
        commandLock.lock()
        defer { commandLock.unlock() }
        guard !stopped else { return }
        stopped = true
        try reset()
    }
}
