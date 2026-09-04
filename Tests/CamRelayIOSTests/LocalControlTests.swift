import CamRelayCore
import Foundation
import XCTest
@testable import CamRelayIOS

final class LocalControlTests: XCTestCase {
    func testCommandsRoundTripThroughNamedSocket() throws {
        let name = "test-\(UUID().uuidString)"
        let server = try LocalControlServer(session: name)
        defer { server.stop() }
        try server.start(handler: { request in
            RelayControlResponse(error: "received \(request.action.rawValue):\(request.fixture ?? "")")
        }, didStop: {})
        let response = try RelayControlClient.send(
            RelayControlRequest(action: .select, fixture: "front"), session: name
        )
        XCTAssertEqual(response.error, "received select:front")
        XCTAssertThrowsError(try LocalControlServer(session: name))
    }

    func testStopResponseArrivesBeforeEndpointShutsDown() throws {
        let name = "test-\(UUID().uuidString)"
        let server = try LocalControlServer(session: name)
        defer { server.stop() }
        let stopped = expectation(description: "stop delivered")
        try server.start(handler: { _ in RelayControlResponse() }, didStop: { stopped.fulfill() })
        let response = try RelayControlClient.send(RelayControlRequest(action: .stop), session: name)
        XCTAssertNil(response.error)
        wait(for: [stopped], timeout: 1)
    }

    func testMissingSessionReadinessWaitTimesOut() throws {
        let start = Date()
        XCTAssertThrowsError(try RelayControlClient.send(
            RelayControlRequest(action: .status, timeout: 0.1),
            session: "test-\(UUID().uuidString)", waitForReady: true
        ))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.09)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testStoppedEndpointIsRemovedAndSessionCanBeReused() throws {
        let name = "test-\(UUID().uuidString)"
        var server: LocalControlServer? = try LocalControlServer(session: name)
        try server?.start(handler: { _ in RelayControlResponse() }, didStop: {})
        server?.stop()
        server = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: try ControlPaths.socket(session: name)))
        let replacement = try LocalControlServer(session: name)
        replacement.stop()
    }

    func testIndependentNamesCannotTakeTheSameSimulatorLease() throws {
        let key = "test-simulator-\(UUID().uuidString)"
        let lease = try RelayLease(key: key)
        try withExtendedLifetime(lease) { XCTAssertThrowsError(try RelayLease(key: key)) }
    }
}
