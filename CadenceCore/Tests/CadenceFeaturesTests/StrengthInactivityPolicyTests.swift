import Foundation
import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct StrengthInactivityPolicyTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private var state: StrengthInactivityPolicy.State { .init(lastMeaningfulActivityAt: t0) }
    typealias P = StrengthInactivityPolicy

    @Test func exactBoundary() {
        #expect(P.evaluate(state: state, now: t0.addingTimeInterval(599), timeoutMinutes: 10, enabled: true) == .continueWorkout)
        #expect(P.evaluate(state: state, now: t0.addingTimeInterval(600), timeoutMinutes: 10, enabled: true) ==
                       .end(at: t0.addingTimeInterval(600)))
        #expect(P.defaultTimeout == 600)
    }

    @Test func nonDefaultDisabledAndLateClock() {
        #expect(P.evaluate(state: state, now: t0.addingTimeInterval(119), timeoutMinutes: 2, enabled: true) == .continueWorkout)
        #expect(P.evaluate(state: state, now: t0.addingTimeInterval(120), timeoutMinutes: 2, enabled: true) ==
                       .end(at: t0.addingTimeInterval(120)))
        #expect(P.evaluate(state: state, now: t0.addingTimeInterval(9999), timeoutMinutes: 2, enabled: false) == .continueWorkout)
        #expect(P.evaluate(state: state, now: t0.addingTimeInterval(9999), timeoutMinutes: 2, enabled: true) ==
                       .end(at: t0.addingTimeInterval(120)))
        #expect(P.deadline(state: state, timeoutMinutes: 0) == t0.addingTimeInterval(60))
    }

    @Test func allowedEventsMoveDeadlineAndPassiveEventsDoNot() {
        for event in StrengthActivityEvent.allCases {
            var s = state
            let later = t0.addingTimeInterval(300)
            s.record(event, at: later)
            #expect(P.deadline(state: s, timeoutMinutes: 10) == later.addingTimeInterval(600), "\(event)")
        }
        for event in StrengthPassiveEvent.allCases {
            var s = state
            s.record(event, at: t0.addingTimeInterval(300))
            #expect(s == state, "\(event)")
        }
    }

    @Test func idempotentAfterExpiry() {
        let first = P.evaluate(state: state, now: t0.addingTimeInterval(601), timeoutMinutes: 10, enabled: true)
        for extra in [700.0, 5000, 100000] {
            #expect(P.evaluate(state: state, now: t0.addingTimeInterval(extra), timeoutMinutes: 10, enabled: true) == first)
        }
    }

    @Test func codableRoundTripAndSettingsMigration() throws {
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(P.State.self, from: data) == state)
        #expect(WorkoutSettings().autoEndOnIdle)
        #expect(WorkoutSettings().idleTimeoutMinutes == 10)
        var off = WorkoutSettings(); off.autoEndOnIdle = false
        let back = try JSONDecoder().decode(WorkoutSettings.self, from: JSONEncoder().encode(off))
        #expect(!back.autoEndOnIdle)
    }

    @Test func onlyStrengthIsGoverned() {
        for t in WorkoutType.allCases { #expect(P.applies(to: t) == (t == .weights), "\(t)") }
        for t in CardioType.allCases { #expect(!P.applies(to: t), "\(t)") }
    }
}
