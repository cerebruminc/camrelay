import CamRelayCore
import CamRelayIOS
import Foundation

private let usage = """
CamRelay supplies an image or video as an iOS Simulator camera feed.

Usage:
  camrelay <media-file>

Examples:
  camrelay ./fixtures/selfie.png
  camrelay ./fixtures/blink.mp4
"""

@main
struct CamRelayCommand {
    nonisolated static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments == ["--help"] || arguments == ["-h"] {
            print(usage)
            return
        }

        if arguments == ["--version"] {
            print("camrelay 0.1.0-dev")
            return
        }

        guard arguments.count == 1 else {
            fail("expected one image or video path\n\n\(usage)", status: 2)
        }

        var terminationSignals = sigset_t()
        sigemptyset(&terminationSignals)
        sigaddset(&terminationSignals, SIGINT)
        sigaddset(&terminationSignals, SIGTERM)
        guard pthread_sigmask(SIG_BLOCK, &terminationSignals, nil) == 0 else {
            fail("could not install signal handling")
        }

        do {
            let fixture = try MediaFixture(path: arguments[0])
            let session = try await IOSRelay().start(fixture: fixture)
            defer { session.stop() }

            print("CamRelay is feeding \(fixture.url.lastPathComponent) throughout \(session.simulator.name).")
            print("Launch or relaunch any app in that Simulator to use the camera feed.")
            print("Press Ctrl-C to stop.")

            var receivedSignal: Int32 = 0
            sigwait(&terminationSignals, &receivedSignal)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private nonisolated static func fail(_ message: String, status: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("camrelay: \(message)\n".utf8))
        exit(status)
    }
}
