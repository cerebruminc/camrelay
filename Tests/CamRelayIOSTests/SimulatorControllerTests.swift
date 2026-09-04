@testable import CamRelayIOS
import Foundation
import Testing

@Test("Selects the only booted Simulator")
func selectsOnlyBootedSimulator() throws {
    let controller = SimulatorController { _ in
        Data("""
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
              {
                "state": "Booted",
                "isAvailable": true,
                "name": "iPhone 17 Pro",
                "udid": "CAMRELAY-TEST-DEVICE"
              }
            ]
          }
        }
        """.utf8)
    }

    let device = try controller.onlyBootedDevice()
    #expect(device.name == "iPhone 17 Pro")
    #expect(device.id == "CAMRELAY-TEST-DEVICE")
}

@Test("Rejects ambiguous booted Simulators")
func rejectsMultipleSimulators() {
    let controller = SimulatorController { _ in
        Data("""
        {
          "devices": {
            "runtime": [
              {"state":"Booted","isAvailable":true,"name":"One","udid":"1"},
              {"state":"Booted","isAvailable":true,"name":"Two","udid":"2"}
            ]
          }
        }
        """.utf8)
    }

    #expect(throws: SimulatorControllerError.multipleBootedDevices([
        SimulatorDevice(id: "1", name: "One", runtimeIdentifier: "runtime"),
        SimulatorDevice(id: "2", name: "Two", runtimeIdentifier: "runtime"),
    ])) {
        _ = try controller.onlyBootedDevice()
    }
}

@Test("Enables the relay for the Simulator launch environment")
func enablesSimulatorRuntime() throws {
    let recorder = CommandRecorder()
    let controller = SimulatorController { arguments in
        recorder.append(arguments)
        return Data()
    }
    let device = SimulatorDevice(id: "DEVICE", name: "Test", runtimeIdentifier: "runtime")

    try controller.enableRuntime(
        on: device,
        runtimeURL: URL(fileURLWithPath: "/tmp/CamRelay Runtime.dylib"),
        frameServerPort: 4321,
        frameFormat: FrameFormat(width: 320, height: 240, bytesPerRow: 1280, framesPerSecond: 15)
    )

    #expect(recorder.commands == [[
        "spawn", "DEVICE", "launchctl", "setenv",
        "CAMRELAY_PORT", "4321",
        "CAMRELAY_WIDTH", "320",
        "CAMRELAY_HEIGHT", "240",
        "CAMRELAY_FPS", "15",
        "DYLD_INSERT_LIBRARIES", "/tmp/CamRelay Runtime.dylib",
    ]])
}

@Test("Disables every Simulator relay environment value")
func disablesSimulatorRuntime() throws {
    let recorder = CommandRecorder()
    let controller = SimulatorController { arguments in
        recorder.append(arguments)
        return Data()
    }
    let device = SimulatorDevice(id: "DEVICE", name: "Test", runtimeIdentifier: "runtime")

    try controller.disableRuntime(on: device)

    #expect(recorder.commands == [[
        "spawn", "DEVICE", "launchctl", "unsetenv",
        "DYLD_INSERT_LIBRARIES",
        "CAMRELAY_PORT",
        "CAMRELAY_WIDTH",
        "CAMRELAY_HEIGHT",
        "CAMRELAY_FPS",
    ]])
}

private final class CommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[String]] = []

    var commands: [[String]] {
        lock.withLock { storage }
    }

    func append(_ command: [String]) {
        lock.withLock { storage.append(command) }
    }
}
