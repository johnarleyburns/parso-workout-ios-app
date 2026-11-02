import Foundation
import CadenceCore

/// Events the owner may report as meaningful activity in a live strength workout.
///
/// Meaningful activity (the ONLY things that reset the inactivity clock):
/// - `userStart` / `userResume`: workout start/resume explicitly chosen by the user;
/// - `setMutation`: a confirmed/logged/edited/deleted strength set;
/// - `structuralEdit`: confirmed add/remove exercise or partner action;
/// - `userPause`: explicit Pause (also covers Finish/Save/discard, which end the session).
///
/// NOT meaningful (must never reset it): app/scene foregrounding, Watch wake, `onAppear`,
/// navigation redraws, timer ticks, Live Activity refresh, HR samples, Watch HR relay or
/// heartbeats, HealthKit callbacks, cache/sync/import events, automatic retries, scrolling.
public enum StrengthActivityEvent: Sendable, CaseIterable {
    case userStart, setMutation, structuralEdit, userResume, userPause
}

/// Passive signals that are explicitly prohibited from counting as activity.
public enum StrengthPassiveEvent: Sendable, CaseIterable {
    case sceneForeground, watchWake, viewAppear, navigationRedraw, timerTick, liveActivityRefresh,
         heartRateSample, watchHeartbeat, healthKitCallback, syncOrImport, automaticRetry, scroll
}

/// Pure, platform-neutral inactivity policy for **strength** workouts only. A strength
/// workout auto-ends at the inactivity deadline (not at the later time a suspended app wakes).
public struct StrengthInactivityPolicy: Sendable, Equatable {
    public static let defaultTimeout: TimeInterval = 10 * 60

    public struct State: Codable, Sendable, Equatable {
        public var lastMeaningfulActivityAt: Date
        public init(lastMeaningfulActivityAt: Date) {
            self.lastMeaningfulActivityAt = lastMeaningfulActivityAt
        }

        /// Records a meaningful event; the only way to move the deadline.
        public mutating func record(_ event: StrengthActivityEvent, at date: Date) {
            lastMeaningfulActivityAt = date
        }

        /// Passive events are accepted so callers can route them uniformly, but never change state.
        public mutating func record(_ event: StrengthPassiveEvent, at date: Date) {}
    }

    public enum Decision: Sendable, Equatable {
        case continueWorkout
        case end(at: Date)
    }

    public static func deadline(state: State, timeoutMinutes: Int) -> Date {
        state.lastMeaningfulActivityAt.addingTimeInterval(TimeInterval(max(1, timeoutMinutes) * 60))
    }

    public static func evaluate(state: State, now: Date, timeoutMinutes: Int,
                                enabled: Bool) -> Decision {
        let deadline = deadline(state: state, timeoutMinutes: timeoutMinutes)
        guard enabled, now >= deadline else { return .continueWorkout }
        return .end(at: deadline)
    }

    /// Only strength is governed; cardio, outdoor cardio, swim, interval and monitoring are not.
    public static func applies(to type: WorkoutType) -> Bool { type == .weights }
    public static func applies(to type: CardioType) -> Bool { false }
}
