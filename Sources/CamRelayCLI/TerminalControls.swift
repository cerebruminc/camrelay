import CamRelayCore
import CamRelayIOS
import Darwin
import Foundation

final class TerminalControls: @unchecked Sendable {
    private let session: IOSRelaySession
    private let shutdown: ShutdownSignal
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var stopped = false
    private var original = termios()

    init(session: IOSRelaySession, shutdown: ShutdownSignal) throws {
        self.session = session
        self.shutdown = shutdown
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw RelayError("Could not read terminal settings.") }
        var mode = original
        mode.c_lflag &= ~tcflag_t(ICANON | ECHO)
        withUnsafeMutableBytes(of: &mode.c_cc) { bytes in
            bytes[Int(VMIN)] = 1
            bytes[Int(VTIME)] = 0
        }
        guard tcsetattr(STDIN_FILENO, TCSANOW, &mode) == 0 else { throw RelayError("Could not enable terminal controls.") }
        for (index, name) in session.status().fixtures.enumerated() {
            print("\(index < 9 ? String(index + 1) : "-")  \(name)")
        }
        print("1-9 select | n next | b previous | r replay | space pause/play | q stop")
        group.enter()
        DispatchQueue(label: "org.camrelay.terminal").async { [self] in
            readKeys()
            group.leave()
        }
    }

    private func readKeys() {
        while !lock.withLock({ stopped }) {
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 && errno == EINTR { continue }
            if ready == 0 { continue }
            guard ready > 0 else { shutdown.request(); return }
            var key: UInt8 = 0
            guard read(STDIN_FILENO, &key, 1) == 1 else { shutdown.request(); return }
            if key == 113 || key == 4 { shutdown.request(); return }
            let state = session.status()
            let request: RelayControlRequest
            switch key {
            case 49...57:
                let index = Int(key - 49)
                guard index < state.fixtures.count else { continue }
                request = RelayControlRequest(action: .select, fixture: state.fixtures[index])
            case 110: request = RelayControlRequest(action: .next)
            case 98: request = RelayControlRequest(action: .previous)
            case 114: request = RelayControlRequest(action: .replay)
            case 32: request = RelayControlRequest(action: state.paused ? .play : .pause)
            default: continue
            }
            let finished = DispatchSemaphore(value: 0)
            Task {
                let response = await session.handle(request)
                CamRelayCommand.printResponse(response, json: false)
                finished.signal()
            }
            finished.wait()
        }
    }

    func stop() {
        let shouldStop = lock.withLock {
            guard !stopped else { return false }
            stopped = true
            return true
        }
        guard shouldStop else { return }
        group.wait()
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
    }

    deinit { stop() }
}
