import CamRelayAndroid
import CamRelayCore
import CamRelayIOS
import Darwin
import Foundation

private let usage = """
CamRelay supplies an image or video as a virtual mobile-device camera feed.

Usage:
  camrelay [--platform ios|android] <media-file>
  camrelay run [--platform ios|android] --session <name> --fixture <name=path> [--fixture <name=path> ...]
  camrelay emulator start|stop --platform android [--avd <name>]
  camrelay select <fixture-name> [--session <name>] [--paused] [--wait-for-frame]
  camrelay replay|next|previous [--session <name>] [--paused] [--wait-for-frame]
  camrelay pause|play [--session <name>] [--wait-for-frame]
  camrelay status|wait|stop [--session <name>] [--json]

Run options:
  --platform <name>         Target ios (default) or android.
  --avd <name>              Choose an Android Virtual Device (automatic when only one exists).
  --initial <fixture-name>   Choose the first fixture (default: first listed).
  --paused                   Hold the initial frame until play (iOS only).
  --no-interactive           Disable terminal controls (automatic without a TTY).

Emulator options:
  --platform android         Manage an Android Emulator separately from a relay.
  --avd <name>              Choose an Android Virtual Device (automatic when only one exists).

Control options:
  --session <name>           Address a running session (default: default).
  --timeout <seconds>        Readiness/delivery timeout, up to 300s (default: 10s).
  --wait-for-frame           Wait for every connected receiver to acknowledge this selection (iOS only).
  --json                     Write a structured status/error response.

Positional paths receive names fixture-1, fixture-2, and so on.
Interactive keys: 1-9 select, n next, b previous, r replay, q stop; space pauses/plays on iOS.

Examples:
  camrelay ./fixtures/checkerboard.png
  camrelay ./fixtures/colors.mp4
  camrelay emulator start --platform android --avd "$AVD_NAME"
  camrelay --platform android --avd "$AVD_NAME" ./fixtures/checkerboard.png
  camrelay emulator stop --platform android --avd "$AVD_NAME"
  camrelay run --session demo --fixture colors=colors.mp4 --fixture pattern=checkerboard.png
  camrelay run --platform android --avd "$AVD_NAME" --session demo --fixture colors=colors.mp4 --fixture pattern=checkerboard.png
  camrelay select pattern --session demo --wait-for-frame --timeout 10s
"""

@main
struct CamRelayCommand {
    nonisolated static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        let command: RelayCommand
        do { command = try RelayCommand.parse(arguments) }
        catch { fail(error.localizedDescription, status: 2, json: arguments.contains("--json")) }
        do {
            switch command {
            case .help: print(usage)
            case .version: print("camrelay 0.1.0-dev")
            case .emulator(let options): try manageEmulator(options)
            case .run(let options): try await run(options)
            case .control(let name, let request, let json, let wait):
                let response = try RelayControlClient.send(request, session: name, waitForReady: wait)
                printResponse(response, json: json)
                if response.error != nil { exit(1) }
            }
        } catch {
            fail(error.localizedDescription, json: arguments.contains("--json"))
        }
    }

    private static func manageEmulator(_ options: EmulatorCommandOptions) throws {
        let lifecycle = try AndroidEmulatorLifecycle()
        let status: AndroidEmulatorStatus
        switch options.action {
        case .start:
            status = try lifecycle.start(avd: options.androidAVD)
            print("Android AVD \(status.device.id) is ready as \(status.serial).")
            print("CamRelay can now attach without restarting the emulator.")
        case .stop:
            status = try lifecycle.stop(avd: options.androidAVD)
            print("Stopped Android AVD \(status.device.id) (\(status.serial)).")
        }
    }

    private static func run(_ options: RelayRunOptions) async throws {
        switch options.platform {
        case .iOS: try await runIOS(options)
        case .android: try runAndroid(options)
        }
    }

    private static func runIOS(_ options: RelayRunOptions) async throws {
        // Readiness and state changes must be visible immediately in CI log pipes.
        setbuf(stdout, nil)
        let shutdown = ShutdownSignal()
        let signals = SignalHandlers(shutdown: shutdown)
        defer { signals.stop() }
        let endpoint = try LocalControlServer(session: options.session)
        defer { endpoint.stop() }
        let session = try await IOSRelay().start(options: options)
        defer { session.stop() }
        try endpoint.start(handler: { request in await session.handle(request) }, didStop: { shutdown.request() })

        print("CamRelay session \(options.session) is ready throughout \(session.simulator.name).")
        print("Launch or relaunch the app once to load the runtime; fixture changes need no relaunch.")
        printResponse(RelayControlResponse(status: session.status()), json: false)

        let terminal: TerminalControls?
        if !options.noInteractive && isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1 {
            terminal = try TerminalControls(session: session, shutdown: shutdown)
        } else {
            terminal = nil
            print("Use camrelay select/status/stop --session \(options.session), or Ctrl-C to stop.")
        }
        defer { terminal?.stop() }
        shutdown.wait()
    }

    private static func runAndroid(_ options: RelayRunOptions) throws {
        // Readiness and state changes must be visible immediately in CI log pipes.
        setbuf(stdout, nil)
        let shutdown = ShutdownSignal()
        let signals = SignalHandlers(shutdown: shutdown)
        defer { signals.stop() }
        let endpoint = try LocalControlServer(session: options.session)
        defer { endpoint.stop() }
        let session = try AndroidRelay().start(options: options)
        defer { session.stop() }
        try endpoint.start(handler: { request in await session.handle(request) }, didStop: { shutdown.request() })

        DispatchQueue.global(qos: .userInitiated).async {
            session.waitUntilExit()
            if !session.stopWasRequested { shutdown.request() }
        }

        print("CamRelay session \(options.session) is ready in Android AVD \(session.device.id) (\(session.serial)).")
        print("Apps use the fixture through standard Android camera APIs; no app changes are needed.")
        print("Stopping CamRelay leaves the Android emulator running.")
        printResponse(RelayControlResponse(status: session.status()), json: false)

        let terminal: TerminalControls?
        if !options.noInteractive && isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1 {
            terminal = try TerminalControls(session: session, shutdown: shutdown, supportsPause: false)
        } else {
            terminal = nil
            print("Use camrelay select/status/stop --session \(options.session), or Ctrl-C to stop.")
        }
        defer { terminal?.stop() }
        shutdown.wait()
    }

    static func printResponse(_ response: RelayControlResponse, json: Bool) {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(response) { print(String(decoding: data, as: UTF8.self)) }
        } else if let error = response.error {
            FileHandle.standardError.write(Data("camrelay: \(error)\n".utf8))
        } else if let state = response.status {
            print("[\(state.session)] \(state.selected) | \(state.paused ? "paused" : "playing") | generation \(state.generation) | receivers \(state.acknowledgedReceivers)/\(state.connectedReceivers)")
            if let error = state.error { FileHandle.standardError.write(Data("camrelay: playback error: \(error)\n".utf8)) }
        }
    }

    private nonisolated static func fail(_ message: String, status: Int32 = 1, json: Bool = false) -> Never {
        printResponse(RelayControlResponse(error: message), json: json)
        exit(status)
    }
}

final class ShutdownSignal: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func request() { semaphore.signal() }
    func wait() { semaphore.wait() }
}

private final class SignalHandlers {
    private let sources: [DispatchSourceSignal]

    init(shutdown: ShutdownSignal) {
        sources = [SIGINT, SIGTERM].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
            source.setEventHandler { shutdown.request() }
            source.resume()
            return source
        }
    }

    func stop() { for source in sources { source.cancel() } }
}
