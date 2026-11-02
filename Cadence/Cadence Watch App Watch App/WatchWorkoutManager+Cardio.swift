import Foundation
import CadenceCore
import CadenceFeatures

extension WatchWorkoutManager {
    /// Starts a cardio workout and records its own timing clock. The returned
    /// value is false when a different workout already owns the Watch's
    /// `HKWorkoutSession`; the cardio still runs and is timed from
    /// `cardioSessionStart`, but it must not stop the owning session. Swimming
    /// instead refuses the start: it requires its own native swimming session
    /// for automatic distance/turn measurements.
    @discardableResult
    func beginCardioWorkout(type rawType: String, cardioType: CardioType? = nil,
                            spec: WorkoutConfigurationSpec? = nil, trackInactivity: Bool = true) -> Bool {
        let ownsSession = startWorkout(type: rawType, cardioType: cardioType, spec: spec)
        if (spec?.kind == .swim || rawType == "swim"), !ownsSession { return false }
        beginCardioSession(ownsSession: ownsSession)
        let type = cardioType ?? CardioType(rawValue: rawType) ?? .other
        let isSwim = spec?.kind == .swim || rawType == "swim" || type == .swim
        if trackInactivity {
            beginCardioInactivityTracking(type: type, isSwim: isSwim, ownsSession: ownsSession)
        }
        return ownsSession
    }

    /// Ends a cardio session. A session that owns the Watch's `HKWorkoutSession`
    /// stops normally; one layered over a phone-started strength workout only
    /// clears its own timing state.
    func finishCardioSession(save: Bool) {
        endCardioInactivityTracking()
        if cardioOwnsSession {
            stopWorkout(save: save)
        } else {
            cardioSessionStart = nil
            cardioOwnsSession = false
        }
    }
}
