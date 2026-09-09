import CamRelayCore
import Foundation

public final class IOSRelaySession: @unchecked Sendable {
    public let simulator: SimulatorDevice
    public let port: UInt16

    private let server: FrameServer
    private let simulatorController: SimulatorController
    private let stateLock = NSLock()
    private let cleanupLock = NSLock()
    private let simulatorLease: RelayLease
    private let commands: PlaybackCommands
    private let name: String
    private let fixtures: [NamedFixture]
    private var stopped = false
    private var cleanedUp = false

    init(
        simulator: SimulatorDevice,
        server: FrameServer,
        simulatorController: SimulatorController,
        simulatorLease: RelayLease,
        name: String,
        fixtures: [NamedFixture]
    ) {
        self.simulator = simulator
        self.server = server
        self.simulatorController = simulatorController
        self.simulatorLease = simulatorLease
        self.name = name
        self.fixtures = fixtures
        commands = PlaybackCommands(server: server, fixtures: fixtures)
        port = server.port
    }

    public func stop() {
        do {
            try stopChecked()
        } catch {
            FileHandle.standardError.write(Data(
                "camrelay: could not remove Simulator-wide activation: \(error.localizedDescription)\n".utf8
            ))
        }
    }

    private func stopChecked() throws {
        cleanupLock.lock()
        defer { cleanupLock.unlock() }
        guard !cleanedUp else { return }
        stateLock.withLock { stopped = true }
        defer { server.stop() }
        try simulatorController.disableRuntime(on: simulator)
        cleanedUp = true
    }

    public func status() -> RelayStatus {
        let state = server.playback.snapshot(at: server.elapsedTime)
        let receivers = server.receiverCounts(for: state.generation)
        let format = server.playback.format
        return RelayStatus(
            session: name, simulator: simulator.name, simulatorID: simulator.id,
            fixtures: fixtures.map(\.name), selected: state.selected, paused: state.paused,
            generation: state.generation, positionSeconds: Double(state.positionNanoseconds) / 1_000_000_000,
            connectedReceivers: receivers.connected, acknowledgedReceivers: receivers.acknowledged,
            width: format.width, height: format.height, framesPerSecond: format.framesPerSecond, error: state.error
        )
    }

    public func handle(_ request: RelayControlRequest) async -> RelayControlResponse {
        do {
            try request.validate()
            if request.action == .stop {
                try await onWorker { try self.stopChecked() }
                return RelayControlResponse(status: status())
            }
            guard !stateLock.withLock({ stopped }) else { throw RelayError("Relay has stopped.") }
            if request.action != .status {
                let generation = try await commands.submit(request)
                if request.waitForFrame {
                    try await onWorker {
                        try self.server.waitForFrame(generation: generation, timeout: request.timeout)
                    }
                }
            }
            return RelayControlResponse(status: status())
        } catch {
            return RelayControlResponse(status: status(), error: error.localizedDescription)
        }
    }
}

public struct IOSRelay {
    private let simulatorController: SimulatorController
    private let environment: [String: String]

    public init(
        simulatorController: SimulatorController = SimulatorController(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.simulatorController = simulatorController
        self.environment = environment
    }

    public func start(fixture: MediaFixture) async throws -> IOSRelaySession {
        var options = RelayRunOptions()
        options.fixtures = [NamedFixture(name: "fixture-1", path: fixture.url.path)]
        return try await start(options: options)
    }

    public func start(options: RelayRunOptions) async throws -> IOSRelaySession {
        guard !options.fixtures.isEmpty else { throw RelayError("Provide at least one fixture.") }
        let simulator = try simulatorController.onlyBootedDevice()
        let lease = try RelayLease(key: "simulator-\(simulator.id)")
        let runtimeURL = try RuntimeLocator(environment: environment).runtimeURL()
        let fixtures = try options.fixtures.map {
            NamedFixture(name: $0.name, path: try MediaFixture(path: $0.path).url.path)
        }
        let initialName = options.initial ?? fixtures[0].name
        guard let initial = fixtures.first(where: { $0.name == initialName }) else {
            throw RelayError("Unknown initial fixture: \(initialName)")
        }
        let prepared = try await prepareFixture(initial)
        let outputFormat = await preferredOutputFormat(fixtures: fixtures, initial: prepared)
        let server = FrameServer(playback: try PlaybackEngine(
            initial: prepared,
            outputFormat: outputFormat,
            paused: options.paused
        ))
        try server.start()

        do {
            try simulatorController.enableRuntime(
                on: simulator,
                runtimeURL: runtimeURL,
                frameServerPort: server.port,
                frameFormat: outputFormat
            )
        } catch {
            server.stop()
            throw error
        }

        return IOSRelaySession(
            simulator: simulator,
            server: server,
            simulatorController: simulatorController,
            simulatorLease: lease,
            name: options.session,
            fixtures: fixtures
        )
    }
}

private func preferredOutputFormat(fixtures: [NamedFixture], initial: PreparedFixture) async -> FrameFormat {
    var candidates: [FrameFormat] = []
    for fixture in fixtures where fixture.name != initial.name {
        do {
            let source = try await MediaFrameSource(fixture: MediaFixture(path: fixture.path))
            candidates.append(source.format)
        } catch {
            // Alternate fixtures remain lazy failures so one bad source does not prevent startup.
        }
    }
    return preferredRelayOutputFormat(initial: initial.source.format, candidates: candidates)
}

private actor PlaybackCommands {
    private let server: FrameServer
    private let fixtures: [NamedFixture]
    private var tail: Task<UInt64, Error>?

    init(server: FrameServer, fixtures: [NamedFixture]) {
        self.server = server
        self.fixtures = fixtures
    }

    func submit(_ request: RelayControlRequest) async throws -> UInt64 {
        let previous = tail
        let task = Task {
            _ = try? await previous?.value
            return try await self.execute(request)
        }
        tail = task
        return try await task.value
    }

    private func execute(_ request: RelayControlRequest) async throws -> UInt64 {
        guard !server.isStopped else { throw RelayError("Relay has stopped.") }
        switch request.action {
        case .pause, .play:
            return server.playback.setPaused(request.action == .pause, at: server.elapsedTime)
        case .select, .replay, .next, .previous:
            let state = server.playback.snapshot(at: server.elapsedTime)
            let currentIndex = fixtures.firstIndex(where: { $0.name == state.selected }) ?? 0
            let name: String
            switch request.action {
            case .select: name = request.fixture ?? ""
            case .next: name = fixtures[(currentIndex + 1) % fixtures.count].name
            case .previous: name = fixtures[(currentIndex + fixtures.count - 1) % fixtures.count].name
            default: name = state.selected
            }
            guard let fixture = fixtures.first(where: { $0.name == name }) else {
                throw RelayError("Unknown fixture: \(name). Available: \(fixtures.map(\.name).joined(separator: ", "))")
            }
            let prepared = try await prepareFixture(fixture)
            guard !server.isStopped else { throw RelayError("Relay stopped while preparing the fixture.") }
            return try server.playback.select(prepared, at: server.elapsedTime, paused: request.paused)
        case .status, .stop:
            throw RelayError("This command does not change playback.")
        }
    }
}

private func onWorker(_ body: @escaping @Sendable () throws -> Void) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        DispatchQueue.global(qos: .userInitiated).async {
            do { try body(); continuation.resume() }
            catch { continuation.resume(throwing: error) }
        }
    }
}

private func prepareFixture(_ fixture: NamedFixture) async throws -> PreparedFixture {
    do {
        let source = try await MediaFrameSource(fixture: MediaFixture(path: fixture.path))
        return try PreparedFixture(name: fixture.name, source: source)
    } catch {
        throw RelayError("Could not load fixture \(fixture.name) (\(fixture.path)): \(error.localizedDescription)")
    }
}

private struct RuntimeLocator {
    let environment: [String: String]

    func runtimeURL() throws -> URL {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let override = environment["CAMRELAY_RUNTIME_PATH"] {
            candidates.append(URL(fileURLWithPath: NSString(string: override).expandingTildeInPath))
        }
        candidates.append(
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appending(path: ".build/runtime/CamRelayRuntime.dylib")
        )
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        candidates.append(executableURL.deletingLastPathComponent().appending(path: "CamRelayRuntime.dylib"))
        candidates.append(executableURL.deletingLastPathComponent().appending(path: "../runtime/CamRelayRuntime.dylib"))

        for candidate in candidates where fileManager.isReadableFile(atPath: candidate.standardizedFileURL.path) {
            return candidate.standardizedFileURL
        }
        throw IOSRelayError.runtimeNotFound
    }
}

enum IOSRelayError: LocalizedError {
    case runtimeNotFound

    var errorDescription: String? {
        switch self {
        case .runtimeNotFound:
            "CamRelayRuntime.dylib was not found. Run ./scripts/build-runtime.sh before using a development build."
        }
    }
}
