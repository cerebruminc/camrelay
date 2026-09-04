import CamRelayCore
import Foundation

public final class IOSRelaySession: @unchecked Sendable {
    public let simulator: SimulatorDevice
    public let port: UInt16

    private let server: FrameServer
    private let simulatorController: SimulatorController
    private let stateLock = NSLock()
    private var stopped = false

    init(
        simulator: SimulatorDevice,
        server: FrameServer,
        simulatorController: SimulatorController
    ) {
        self.simulator = simulator
        self.server = server
        self.simulatorController = simulatorController
        port = server.port
    }

    public func stop() {
        let shouldStop = stateLock.withLock {
            guard !stopped else { return false }
            stopped = true
            return true
        }
        guard shouldStop else { return }
        do {
            try simulatorController.disableRuntime(on: simulator)
        } catch {
            FileHandle.standardError.write(Data(
                "camrelay: could not remove Simulator-wide activation: \(error.localizedDescription)\n".utf8
            ))
        }
        server.stop()
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
        let simulator = try simulatorController.onlyBootedDevice()
        let runtimeURL = try RuntimeLocator(environment: environment).runtimeURL()
        let source = try await MediaFrameSource(fixture: fixture)
        let server = FrameServer(source: source)
        try server.start()

        do {
            try simulatorController.enableRuntime(
                on: simulator,
                runtimeURL: runtimeURL,
                frameServerPort: server.port,
                frameFormat: source.format
            )
        } catch {
            server.stop()
            throw error
        }

        return IOSRelaySession(
            simulator: simulator,
            server: server,
            simulatorController: simulatorController
        )
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
