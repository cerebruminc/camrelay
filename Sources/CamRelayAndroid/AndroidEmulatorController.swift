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
    case notRunning(String)
    case alreadyRunning(String, serial: String)
    case multipleRunning(String, serials: [String])

    public var errorDescription: String? {
        switch self {
        case .noAVDs:
            "No Android Virtual Devices found. Create one in Android Studio and try again."
        case .unknownAVD(let name, let available):
            "Android AVD \(name) was not found. Available: \(available.joined(separator: ", "))."
        case .multipleAVDs(let devices):
            "More than one Android AVD is available: \(devices.joined(separator: ", ")). Choose one with --avd."
        case .notRunning(let name):
            "Android AVD \(name) is not running with CamRelay camera support."
        case .alreadyRunning(let name, let serial):
            "Android AVD \(name) is already running as \(serial)."
        case .multipleRunning(let name, let serials):
            "Android AVD \(name) has more than one running instance: \(serials.joined(separator: ", ")). Stop the extra instance and try again."
        }
    }
}

public struct AndroidEmulatorStatus: Equatable, Sendable {
    public let device: AndroidVirtualDevice
    public let serial: String

    public init(device: AndroidVirtualDevice, serial: String) {
        self.device = device
        self.serial = serial
    }
}

struct AndroidEmulatorConnection: Sendable {
    let device: AndroidVirtualDevice
    let endpoint: EmulatorControlEndpoint
    let processIdentifier: Int32
    let discoveryURL: URL
    let adbURL: URL
    let environment: [String: String]

    var isRunning: Bool {
        FileManager.default.fileExists(atPath: discoveryURL.path)
            && androidProcessIsRunning(processIdentifier)
    }

    func waitUntilBooted(timeout: TimeInterval = 120) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let output = try? runAndroidCommand(
                adbURL,
                arguments: ["-s", endpoint.serial, "shell", "getprop", "sys.boot_completed"],
                environment: environment
            ), String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                return
            }
            guard isRunning else {
                throw RelayError("Android AVD \(device.id) exited before Android finished booting.")
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        throw RelayError("Timed out waiting for Android AVD \(device.id) to boot.")
    }

    func waitUntilEnvironmentCamerasAvailable(timeout: TimeInterval = 30) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let output = try? runAndroidCommand(
                adbURL,
                arguments: ["-s", endpoint.serial, "shell", "dumpsys", "media.camera"],
                environment: environment
            ), mappedCameraDeviceCount(in: String(decoding: output, as: UTF8.self)) >= 2 {
                return
            }
            guard isRunning else {
                throw RelayError("Android AVD \(device.id) exited before its environment cameras became available.")
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        throw RelayError("Timed out waiting for both environment cameras in Android AVD \(device.id).")
    }

    func waitUntilExit() {
        while isRunning { Thread.sleep(forTimeInterval: 0.25) }
    }

    func stop(timeout: TimeInterval = 30) throws {
        guard isRunning else { return }
        _ = try runAndroidCommand(
            adbURL,
            arguments: ["-s", endpoint.serial, "emu", "kill"],
            environment: environment
        )
        let deadline = Date().addingTimeInterval(timeout)
        while isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard !isRunning else {
            throw RelayError("Timed out waiting for Android AVD \(device.id) to stop.")
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
            discoveryDirectory: try discoveryDirectory(),
            adbURL: sdk.adbURL,
            device: device
        )
    }

    func runningConnection(for device: AndroidVirtualDevice) throws -> AndroidEmulatorConnection {
        let matches = try runningConnections().filter { $0.device.id == device.id }
        switch matches.count {
        case 0: throw AndroidEmulatorControllerError.notRunning(device.id)
        case 1: return matches[0]
        default:
            throw AndroidEmulatorControllerError.multipleRunning(
                device.id, serials: matches.map(\.endpoint.serial).sorted()
            )
        }
    }

    func connectionIfRunning(for device: AndroidVirtualDevice) throws -> AndroidEmulatorConnection? {
        do { return try runningConnection(for: device) }
        catch AndroidEmulatorControllerError.notRunning { return nil }
    }

    private func runningConnections() throws -> [AndroidEmulatorConnection] {
        let directory = try discoveryDirectory()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        guard isPrivateAndroidPath(directory, expectedType: .typeDirectory) else {
            throw RelayError("Android Emulator control directory is not private and owned by the current user: \(directory.path)")
        }

        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard url.lastPathComponent.hasPrefix("pid_"), url.pathExtension == "ini",
                  isPrivateAndroidPath(url, expectedType: .typeRegular),
                  let processIdentifier = androidProcessIdentifier(from: url),
                  androidProcessIsRunning(processIdentifier),
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  let discovery = emulatorDiscovery(from: text),
                  let device = try? selectAVD(named: discovery.avdID) else { return nil }
            return AndroidEmulatorConnection(
                device: device,
                endpoint: discovery.endpoint,
                processIdentifier: processIdentifier,
                discoveryURL: url,
                adbURL: sdk.adbURL,
                environment: environment
            )
        }
    }

    private func discoveryDirectory() throws -> URL {
        guard let home = environment["HOME"], !home.isEmpty else {
            throw RelayError("HOME is required to locate Android Emulator control information.")
        }
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Caches/TemporaryItems/avd/running")
            .standardizedFileURL
    }
}

public struct AndroidEmulatorLifecycle {
    private let controller: AndroidEmulatorController

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let sdk = try AndroidSDK(environment: environment)
        controller = AndroidEmulatorController(sdk: sdk, environment: environment)
    }

    public func start(avd requestedName: String?) throws -> AndroidEmulatorStatus {
        let device = try controller.selectAVD(named: requestedName)
        try RelayCommand.validateName(device.id, kind: "AVD name")
        let lease = try RelayLease(key: "android-emulator-\(device.id)")
        return try withExtendedLifetime(lease) {
            if let running = try controller.connectionIfRunning(for: device) {
                throw AndroidEmulatorControllerError.alreadyRunning(device.id, serial: running.endpoint.serial)
            }

            let emulator = try controller.launch(device)
            do {
                let connection = try emulator.waitForConnection()
                try connection.waitUntilBooted()
                try connection.waitUntilEnvironmentCamerasAvailable()
                emulator.leaveRunning()
                return AndroidEmulatorStatus(device: device, serial: connection.endpoint.serial)
            } catch {
                emulator.stop()
                throw error
            }
        }
    }

    public func stop(avd requestedName: String?) throws -> AndroidEmulatorStatus {
        let device = try controller.selectAVD(named: requestedName)
        try RelayCommand.validateName(device.id, kind: "AVD name")
        let lease = try RelayLease(key: "android-emulator-\(device.id)")
        return try withExtendedLifetime(lease) {
            let connection = try controller.runningConnection(for: device)
            try connection.stop()
            return AndroidEmulatorStatus(device: device, serial: connection.endpoint.serial)
        }
    }
}

public final class AndroidEmulatorProcess: @unchecked Sendable {
    public let avdID: String

    private let process: Process
    private let device: AndroidVirtualDevice
    private let discoveryURL: URL
    private let adbURL: URL
    private let environment: [String: String]
    private let exitGroup = DispatchGroup()
    private let lock = NSLock()
    private var stopRequested = false
    private var ownsProcess = true

    init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        discoveryDirectory: URL,
        adbURL: URL,
        device: AndroidVirtualDevice
    ) throws {
        avdID = device.id
        self.device = device
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
            throw RelayError("Could not launch Android AVD \(device.id): \(error.localizedDescription)")
        }
        discoveryURL = discoveryDirectory.appendingPathComponent("pid_\(process.processIdentifier).ini")
    }

    func waitForConnection(timeout: TimeInterval = 30) throws -> AndroidEmulatorConnection {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let text = try? String(contentsOf: discoveryURL, encoding: .utf8),
               let discovery = emulatorDiscovery(from: text), discovery.avdID == device.id {
                return AndroidEmulatorConnection(
                    device: device,
                    endpoint: discovery.endpoint,
                    processIdentifier: process.processIdentifier,
                    discoveryURL: discoveryURL,
                    adbURL: adbURL,
                    environment: environment
                )
            }
            guard process.isRunning else {
                throw RelayError("Android AVD \(avdID) exited before its control endpoint became ready. Make sure the AVD is not already running.")
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        throw RelayError("Timed out waiting for Android AVD \(avdID) control endpoint.")
    }

    func leaveRunning() {
        lock.withLock { ownsProcess = false }
    }

    public func waitUntilExit() {
        exitGroup.wait()
    }

    public func stop() {
        let shouldTerminate = lock.withLock {
            guard ownsProcess, !stopRequested else { return false }
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

private struct EmulatorDiscovery {
    let avdID: String
    let endpoint: EmulatorControlEndpoint
}

private func emulatorDiscovery(from discovery: String) -> EmulatorDiscovery? {
    let values = parseINI(discovery)
    guard let avdID = values["avd.id"], !avdID.isEmpty,
          let rawPort = values["grpc.port"], let port = UInt16(rawPort),
          let token = values["grpc.token"], !token.isEmpty,
          let rawSerial = values["port.serial"], UInt16(rawSerial) != nil else { return nil }
    return EmulatorDiscovery(
        avdID: avdID,
        endpoint: EmulatorControlEndpoint(port: port, token: token, serial: "emulator-\(rawSerial)")
    )
}

func emulatorEndpoint(from discovery: String) -> EmulatorControlEndpoint? {
    emulatorDiscovery(from: discovery)?.endpoint
}

private func androidProcessIdentifier(from url: URL) -> Int32? {
    let name = url.deletingPathExtension().lastPathComponent
    guard name.hasPrefix("pid_") else { return nil }
    return Int32(name.dropFirst(4))
}

private func androidProcessIsRunning(_ processIdentifier: Int32) -> Bool {
    guard processIdentifier > 0 else { return false }
    if kill(processIdentifier, 0) == 0 { return true }
    return errno == EPERM
}

private func isPrivateAndroidPath(_ url: URL, expectedType: FileAttributeType) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          attributes[.type] as? FileAttributeType == expectedType,
          let owner = attributes[.ownerAccountID] as? NSNumber,
          owner.uint32Value == getuid(),
          let permissions = attributes[.posixPermissions] as? NSNumber else { return false }
    return permissions.intValue & 0o077 == 0
}

func mappedCameraDeviceCount(in cameraServiceDump: String) -> Int {
    cameraServiceDump.split(whereSeparator: \Character.isNewline).count { line in
        let text = line.trimmingCharacters(in: .whitespaces)
        return text.hasPrefix("Device ") && text.contains(" maps to ")
    }
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
