import XCTest
import CadenceFeatures

/// Field test 2026-10-03: a Watch workout session was still recording 27 hours after the
/// workout ended, with nothing on either device showing it.
final class WatchSessionOwnershipTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func input(running: Bool = true, age: TimeInterval, type: String? = "strength",
                       screen: Bool = false, phone: Bool = false,
                       resumable: Bool = false) -> WatchSessionOwnership.Input {
        .init(isRunning: running, startedAt: now.addingTimeInterval(-age), workoutType: type,
              workoutScreenVisible: screen, ownedByPhone: phone, hasResumableStrength: resumable)
    }

    func testFieldBugTwentySevenHourOrphanIsEnded() {
        let verdict = WatchSessionOwnership.verdict(input(age: 27 * 3600), now: now)
        XCTAssertEqual(verdict, .endNow(startedAt: now.addingTimeInterval(-27 * 3600)))
    }

    func testNoSessionIsOwned() {
        XCTAssertEqual(WatchSessionOwnership.verdict(input(running: false, age: 99 * 3600), now: now), .owned)
    }

    func testVisibleWorkoutScreenOwnsEvenALongSession() {
        XCTAssertEqual(WatchSessionOwnership.verdict(input(age: 5 * 3600, screen: true), now: now), .owned)
    }

    func testRecentUnownedSessionIsOfferedNotEnded() {
        XCTAssertEqual(WatchSessionOwnership.verdict(input(age: 600, type: "run"), now: now),
                       .unowned(startedAt: now.addingTimeInterval(-600)))
    }

    func testResumableStrengthOwnsItsSessionUntilAbandoned() {
        XCTAssertEqual(WatchSessionOwnership.verdict(input(age: 1800, resumable: true), now: now), .owned)
        XCTAssertEqual(WatchSessionOwnership.verdict(input(age: 5 * 3600, resumable: true), now: now),
                       .endNow(startedAt: now.addingTimeInterval(-5 * 3600)))
    }

    func testResumableStrengthDoesNotOwnACardioSession() {
        XCTAssertEqual(WatchSessionOwnership.verdict(input(age: 600, type: "cycle", resumable: true), now: now),
                       .unowned(startedAt: now.addingTimeInterval(-600)))
    }

    func testPhoneOwnedSessionEndsOnlyAfterItsStopIsClearlyLost() {
        XCTAssertEqual(WatchSessionOwnership.verdict(input(age: 5 * 3600, phone: true), now: now), .owned)
        XCTAssertEqual(WatchSessionOwnership.verdict(input(age: 7 * 3600, phone: true), now: now),
                       .endNow(startedAt: now.addingTimeInterval(-7 * 3600)))
    }

    func testBackgroundVerdictOnlyEndsAbandonedSessions() {
        XCTAssertEqual(WatchSessionOwnership.backgroundVerdict(
            startedAt: now.addingTimeInterval(-600), ownedByPhone: false, now: now), .owned)
        XCTAssertEqual(WatchSessionOwnership.backgroundVerdict(
            startedAt: now.addingTimeInterval(-27 * 3600), ownedByPhone: false, now: now),
            .endNow(startedAt: now.addingTimeInterval(-27 * 3600)))
    }
}
