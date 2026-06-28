import Foundation
import Observation
import CadenceCore

/// Owns the contribution-prompt lifecycle: the persisted engagement counters, the
/// pure decision (`CadenceCore.ContributionPromptEngine`), and the show/snooze/
/// opt-out state. The view layer (Home only) observes `showToast`; genuine workout
/// completions bump the counter via the static `recordWorkoutCompleted`.
///
/// It owns its `ContributionStore` so the app needs a single `@State` and one
/// shared store instance (Settings and the Support screen read `coordinator.store`).
@MainActor
@Observable
final class ContributionCoordinator {
    /// The StoreKit layer, shared by the Support screen and Settings.
    let store: ContributionStore

    var showToast = false

    @ObservationIgnored private let engine = ContributionPromptEngine()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var promptedThisSession = false

    private enum Key {
        static let workouts      = "contrib.workoutsCompleted"
        static let sessions      = "contrib.sessionCount"
        static let optedOut      = "contrib.optedOut"
        static let lastPrompt    = "contrib.lastPromptAt"
        static let launchesSince = "contrib.launchesSinceLastPrompt"
    }

    init(defaults: UserDefaults = .standard) {
        self.store = ContributionStore()
        self.defaults = defaults
    }

    /// Once per launch: a new session, a launch toward the snooze gate, reset the
    /// once-per-session guard.
    func beginSession() {
        defaults.set(defaults.integer(forKey: Key.sessions) + 1, forKey: Key.sessions)
        defaults.set(defaults.integer(forKey: Key.launchesSince) + 1, forKey: Key.launchesSince)
        promptedThisSession = false
    }

    /// Bump the engagement counter on each genuine completed workout. Static so the
    /// call sites needn't hold a coordinator reference.
    static func recordWorkoutCompleted(defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: Key.workouts) + 1, forKey: Key.workouts)
    }

    /// Evaluate at a natural break (Home, app active, no workout in progress);
    /// raises the toast iff the engine approves.
    func evaluate() {
        guard !showToast else { return }
        let inputs = ContributionPromptEngine.Inputs(
            workoutsCompleted: defaults.integer(forKey: Key.workouts),
            sessionCount: defaults.integer(forKey: Key.sessions),
            isSupporter: store.isSupporter,
            optedOut: defaults.bool(forKey: Key.optedOut),
            promptedThisSession: promptedThisSession,
            lastPromptAt: defaults.object(forKey: Key.lastPrompt) as? Date,
            launchesSinceLastPrompt: defaults.integer(forKey: Key.launchesSince),
            now: Date())
        guard engine.shouldPrompt(inputs) else { return }
        promptedThisSession = true
        defaults.set(Date(), forKey: Key.lastPrompt)   // arms the 7-day snooze
        defaults.set(0, forKey: Key.launchesSince)      // arms the 5-launch snooze
        showToast = true
    }

    func dismissToast() { showToast = false }                                        // "Maybe later"
    func optOutForever() { defaults.set(true, forKey: Key.optedOut); showToast = false } // "Don't ask again"
}
