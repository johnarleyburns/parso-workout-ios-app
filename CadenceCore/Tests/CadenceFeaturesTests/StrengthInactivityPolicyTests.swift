import XCTest
import CadenceCore
import CadenceFeatures

final class StrengthInactivityPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private var state: StrengthInactivityPolicy.State { .init(lastMeaningfulActivityAt: t0) }
    typealias P = StrengthInactivityPolicy

    func testExactBoundary() {
        XCTAssertEqual(P.evaluate(state: state, now: t0.addingTimeInterval(599), timeoutMinutes: 10, enabled: true), .continueWorkout)
        XCTAssertEqual(P.evaluate(state: state, now: t0.addingTimeInterval(600), timeoutMinutes: 10, enabled: true),
                       .end(at: t0.addingTimeInterval(600)))
        XCTAssertEqual(P.defaultTimeout, 600)
    }

    func testNonDefaultDisabledAndLateClock() {
        XCTAssertEqual(P.evaluate(state: state, now: t0.addingTimeInterval(119), timeoutMinutes: 2, enabled: true), .continueWorkout)
        XCTAssertEqual(P.evaluate(state: state, now: t0.addingTimeInterval(120), timeoutMinutes: 2, enabled: true),
                       .end(at: t0.addingTimeInterval(120)))
        XCTAssertEqual(P.evaluate(state: state, now: t0.addingTimeInterval(9999), timeoutMinutes: 2, enabled: false), .continueWorkout)
        XCTAssertEqual(P.evaluate(state: state, now: t0.addingTimeInterval(9999), timeoutMinutes: 2, enabled: true),
                       .end(at: t0.addingTimeInterval(120)))
        XCTAssertEqual(P.deadline(state: state, timeoutMinutes: 0), t0.addingTimeInterval(60))
    }

    func testAllowedEventsMoveDeadlineAndPassiveEventsDoNot() {
        for event in StrengthActivityEvent.allCases {
            var s = state
            let later = t0.addingTimeInterval(300)
            s.record(event, at: later)
            XCTAssertEqual(P.deadline(state: s, timeoutMinutes: 10), later.addingTimeInterval(600), "\(event)")
        }
        for event in StrengthPassiveEvent.allCases {
            var s = state
            s.record(event, at: t0.addingTimeInterval(300))
            XCTAssertEqual(s, state, "\(event)")
        }
    }

    func testIdempotentAfterExpiry() {
        let first = P.evaluate(state: state, now: t0.addingTimeInterval(601), timeoutMinutes: 10, enabled: true)
        for extra in [700.0, 5000, 100000] {
            XCTAssertEqual(P.evaluate(state: state, now: t0.addingTimeInterval(extra), timeoutMinutes: 10, enabled: true), first)
        }
    }

    func testCodableRoundTripAndSettingsMigration() throws {
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(P.State.self, from: data), state)
        XCTAssertTrue(WorkoutSettings().autoEndOnIdle)
        XCTAssertEqual(WorkoutSettings().idleTimeoutMinutes, 10)
        var off = WorkoutSettings(); off.autoEndOnIdle = false
        let back = try JSONDecoder().decode(WorkoutSettings.self, from: JSONEncoder().encode(off))
        XCTAssertFalse(back.autoEndOnIdle)
    }

    func testOnlyStrengthIsGoverned() {
        for t in WorkoutType.allCases { XCTAssertEqual(P.applies(to: t), t == .weights, "\(t)") }
        for t in CardioType.allCases { XCTAssertFalse(P.applies(to: t), "\(t)") }
    }
}
