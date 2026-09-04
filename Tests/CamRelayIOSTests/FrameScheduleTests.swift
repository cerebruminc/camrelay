import XCTest
@testable import CamRelayIOS

final class FrameScheduleTests: XCTestCase {
    func testTargetUptimeUsesMediaTimestampFromFixedOrigin() {
        let schedule = FrameSchedule(
            mediaOriginNanoseconds: 500_000_000,
            uptimeOriginNanoseconds: 10_000_000_000
        )

        XCTAssertEqual(
            schedule.targetUptimeNanoseconds(for: 533_333_333),
            10_033_333_333
        )
        XCTAssertEqual(
            schedule.targetUptimeNanoseconds(for: 1_500_000_000),
            11_000_000_000
        )
    }

    func testFrameExpiresOnlyAfterItsMediaIntervalEnds() {
        let schedule = FrameSchedule(
            mediaOriginNanoseconds: 0,
            uptimeOriginNanoseconds: 1_000_000_000
        )

        XCTAssertFalse(
            schedule.isExpired(
                presentationTimeNanoseconds: 33_333_333,
                durationNanoseconds: 33_333_333,
                at: 1_066_666_665
            )
        )
        XCTAssertTrue(
            schedule.isExpired(
                presentationTimeNanoseconds: 33_333_333,
                durationNanoseconds: 33_333_333,
                at: 1_066_666_666
            )
        )
    }
}
