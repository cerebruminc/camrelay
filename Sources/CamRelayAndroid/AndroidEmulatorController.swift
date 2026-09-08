#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import CamRelayCore
import Foundation

public struct AndroidVirtualDevice: Equatable, Sendable {
    public let id: String
    public let directoryURL: URL
}

public enum AndroidEmulatorControllerError: LocalizedError, Equatable {
    case noAVDs
    case unknownAVD(String, available: [String])
    case multipleAVDs([String])

    public var errorDescription: String? {
        switch self {
        case .noAVDs:
            "No Android Virtual Devices found. Create one in Android Studio and try again."
        case .unknownAVD(let name, let available):
            "Android AVD \(name) was not found. Available: \(available.joined(separator: ", "))."
        case .multipleAVDs(let devices):
            "More than one Android AVD is available: \(devices.joined(separator: ", ")). Choose one with --avd."
        }
    }
}

public struct AndroidEmulatorController: Sendable {
    private let sdk: AndroidSDK
    private let environment: [String: String]
    private let listRunner: @Sendable () throws -> Data

    public init(
        sdk: AndroidSDK,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.sdk = sdk
        self.environment = environment
        listRunner = { try runAndroidCommand(sdk.emulatorURL, arguments: ["-list-avds"], environment: environment) }
    }

    init(
        sdk: AndroidSDK,
        environment: [String: String],
        listRunner: @escaping @Sendable () throws -> Data
    ) {
        self.sdk = sdk
        self.environment = environment
        self.listRunner = listRunner
    }

    public func selectAVD(named requestedName: String?) throws -> AndroidVirtualDevice {
        let available = String(decoding: try listRunner(), as: UTF8.self)
            .split(whereSeparator: \Character.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()

        let name: String
        if let requestedName {
            guard available.contains(requestedName) else {
                throw AndroidEmulatorControllerError.unknownAVD(requestedName, available: available)
            }
            name = requestedName
        } else {
            switch available.count {
            case 0: throw AndroidEmulatorControllerError.noAVDs
            case 1: name = available[0]
            default: throw AndroidEmulatorControllerError.multipleAVDs(available)
            }
        }
        return AndroidVirtualDevice(id: name, directoryURL: try sdk.avdDirectory(named: name))
    }

    public func launch(_ device: AndroidVirtualDevice) throws -> AndroidEmulatorProcess {
        let discoveryDirectory: URL
        if let home = environment["HOME"], !home.isEmpty {
            discoveryDirectory = URL(fileURLWithPath: home)
                .appendingPathComponent("Library/Caches/TemporaryItems/avd/running")
        } else {
            throw RelayError("HOME is required to locate Android Emulator control information.")
        }
        return try AndroidEmulatorProcess(
            executableURL: sdk.emulatorURL,
            arguments: [
                "@\(device.id)",
                "-camera-back", "environment",
                "-camera-front", "environment",
                "-grpc", "0",
                "-grpc-use-token",
                "-no-snapshot",
                "-no-boot-anim",
            ],
            environment: environment,
            discoveryDirectory: discoveryDirectory,
            adbURL: sdk.adbURL,
            avdID: device.id
        )
    }
}

public final class AndroidEmulatorProcess: @unchecked Sendable {
    public let avdID: String

    private let process: Process
    private let discoveryURL: URL
    private let adbURL: URL
    private let environment: [String: String]
    private let exitGroup = DispatchGroup()
    private let lock = NSLock()
    private var stopRequested = false

    init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        discoveryDirectory: URL,
        adbURL: URL,
        avdID: String
    ) throws {
        self.avdID = avdID
        self.adbURL = adbURL
        self.environment = environment

        let process = Process()
        self.process = process
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        exitGroup.enter()
        process.terminationHandler = { [exitGroup] _ in exitGroup.leave() }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            exitGroup.leave()
            throw RelayError("Could not launch Android AVD \(avdID): \(error.localizedDescription)")
        }
        discoveryURL = discoveryDirectory.appendingPathComponent("pid_\(process.processIdentifier).ini")
    }

    func waitForControl(timeout: TimeInterval = 30) throws -> EmulatorControlEndpoint {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let text = try? String(contentsOf: discoveryURL, encoding: .utf8),
               let endpoint = emulatorEndpoint(from: text) {
                return endpoint
            }
            guard process.isRunning else {
                throw RelayError("Android AVD \(avdID) exited before its control endpoint became ready. Make sure the AVD is not already running.")
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        throw RelayError("Timed out waiting for Android AVD \(avdID) control endpoint.")
    }

    func waitUntilBooted(endpoint: EmulatorControlEndpoint, timeout: TimeInterval = 120) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let output = try? runAndroidCommand(
                adbURL,
                arguments: ["-s", endpoint.serial, "shell", "getprop", "sys.boot_completed"],
                environment: environment
            ), String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                return
            }
            guard process.isRunning else {
                throw RelayError("Android AVD \(avdID) exited before Android finished booting.")
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        throw RelayError("Timed out waiting for Android AVD \(avdID) to boot.")
    }

    public func waitUntilExit() {
        exitGroup.wait()
    }

    public func stop() {
        let shouldTerminate = lock.withLock {
            guard !stopRequested else { return false }
            stopRequested = true
            return process.isRunning
        }
        guard shouldTerminate else { return }
        process.interrupt()
        if exitGroup.wait(timeout: .now() + 10) == .timedOut {
            process.terminate()
            if exitGroup.wait(timeout: .now() + 20) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exitGroup.wait()
            }
        }
    }

    deinit { stop() }
}

func emulatorEndpoint(from discovery: String) -> EmulatorControlEndpoint? {
    let values = parseINI(discovery)
    guard let rawPort = values["grpc.port"], let port = UInt16(rawPort),
          let token = values["grpc.token"], !token.isEmpty,
          let rawSerial = values["port.serial"], UInt16(rawSerial) != nil else { return nil }
    return EmulatorControlEndpoint(port: port, token: token, serial: "emulator-\(rawSerial)")
}

private func runAndroidCommand(
    _ executableURL: URL,
    arguments: [String],
    environment: [String: String] = ProcessInfo.processInfo.environment
) throws -> Data {
    let process = Process()
    let output = Pipe()
    let errorOutput = Pipe()
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = output
    process.standardError = errorOutput
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(decoding: errorData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw RelayError("\(executableURL.lastPathComponent) failed: \(message.isEmpty ? "exit status \(process.terminationStatus)" : message)")
    }
    return outputData
}
