import Foundation

public struct SimulatorDevice: Equatable, Sendable {
    public let id: String
    public let name: String
    public let runtimeIdentifier: String

    public init(id: String, name: String, runtimeIdentifier: String) {
        self.id = id
        self.name = name
        self.runtimeIdentifier = runtimeIdentifier
    }
}

public struct SimulatorController: Sendable {
    private static let relayEnvironmentKeys = [
        "DYLD_INSERT_LIBRARIES",
        "CAMRELAY_PORT",
        "CAMRELAY_WIDTH",
        "CAMRELAY_HEIGHT",
        "CAMRELAY_FPS",
    ]

    private let commandRunner: @Sendable ([String]) throws -> Data

    public init(commandRunner: @escaping @Sendable ([String]) throws -> Data = SimulatorController.runSimctl) {
        self.commandRunner = commandRunner
    }

    public func onlyBootedDevice() throws -> SimulatorDevice {
        let data = try commandRunner(["list", "devices", "booted", "--json"])
        let list = try JSONDecoder().decode(DeviceList.self, from: data)
        let bootedDevices = list.devices.flatMap { runtimeIdentifier, devices in
            devices.compactMap { device -> SimulatorDevice? in
                guard device.state == "Booted", device.isAvailable != false else {
                    return nil
                }
                return SimulatorDevice(
                    id: device.udid,
                    name: device.name,
                    runtimeIdentifier: runtimeIdentifier
                )
            }
        }

        switch bootedDevices.count {
        case 0:
            throw SimulatorControllerError.noBootedDevice
        case 1:
            return bootedDevices[0]
        default:
            throw SimulatorControllerError.multipleBootedDevices(bootedDevices)
        }
    }

    func enableRuntime(
        on device: SimulatorDevice,
        runtimeURL: URL,
        frameServerPort: UInt16,
        frameFormat: FrameFormat
    ) throws {
        _ = try commandRunner([
            "spawn",
            device.id,
            "launchctl",
            "setenv",
            "CAMRELAY_PORT",
            String(frameServerPort),
            "CAMRELAY_WIDTH",
            String(frameFormat.width),
            "CAMRELAY_HEIGHT",
            String(frameFormat.height),
            "CAMRELAY_FPS",
            String(frameFormat.framesPerSecond),
            "DYLD_INSERT_LIBRARIES",
            runtimeURL.path,
        ])
    }

    func disableRuntime(on device: SimulatorDevice) throws {
        _ = try commandRunner([
            "spawn",
            device.id,
            "launchctl",
            "unsetenv",
        ] + Self.relayEnvironmentKeys)
    }

    public static func runSimctl(arguments: [String]) throws -> Data {
        try runSimctl(arguments: arguments, environment: ProcessInfo.processInfo.environment)
    }

    private static func runSimctl(arguments: [String], environment: [String: String]) throws -> Data {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        process.environment = environment
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let error = standardError.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: error, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SimulatorControllerError.commandFailed(message)
        }
        return output
    }
}

public enum SimulatorControllerError: LocalizedError, Equatable {
    case noBootedDevice
    case multipleBootedDevices([SimulatorDevice])
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noBootedDevice:
            "No booted iOS Simulator found. Boot one and run CamRelay again."
        case .multipleBootedDevices(let devices):
            "More than one iOS Simulator is booted: \(devices.map(\.name).joined(separator: ", ")). Shut down the extras and try again."
        case .commandFailed(let message):
            "simctl failed: \(message)"
        }
    }
}

private struct DeviceList: Decodable {
    let devices: [String: [Device]]
}

private struct Device: Decodable {
    let state: String
    let isAvailable: Bool?
    let name: String
    let udid: String
}
