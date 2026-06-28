import Foundation

/// Pure decision logic for *when* to show the contribution prompt. No UI, no
/// StoreKit, no I/O — deterministic given its inputs, so it's fully unit-tested
/// (the app layer owns the persisted counters in UserDefaults).
///
/// Ported from the Parso Radio app's ContributionPromptEngine; the per-engagement
/// counter is "workouts completed" here (radio counts tracks played).
///
/// Rules:
///  • Never if the user opted out ("Don't ask again") or is already a supporter.
///  • Never on the first session, and at most once per session.
///  • Only after genuine engagement: ≥ minWorkouts completed AND ≥ minSessions.
///  • After any prompt, snooze BOTH ≥ snoozeDays AND ≥ snoozeLaunches before
///    re-asking (so "Maybe later" means a real break, not next-launch nagging).
public struct ContributionPromptEngine: Sendable {
    public var minWorkouts = 6
    public var minSessions = 2
    public var snoozeDays: Double = 7
    public var snoozeLaunches = 5

    public init() {}

    public struct Inputs: Equatable, Sendable {
        public var workoutsCompleted: Int
        public var sessionCount: Int
        public var isSupporter: Bool
        public var optedOut: Bool
        public var promptedThisSession: Bool
        public var lastPromptAt: Date?
        public var launchesSinceLastPrompt: Int
        public var now: Date

        public init(workoutsCompleted: Int, sessionCount: Int, isSupporter: Bool,
                    optedOut: Bool, promptedThisSession: Bool, lastPromptAt: Date?,
                    launchesSinceLastPrompt: Int, now: Date = Date()) {
            self.workoutsCompleted = workoutsCompleted
            self.sessionCount = sessionCount
            self.isSupporter = isSupporter
            self.optedOut = optedOut
            self.promptedThisSession = promptedThisSession
            self.lastPromptAt = lastPromptAt
            self.launchesSinceLastPrompt = launchesSinceLastPrompt
            self.now = now
        }
    }

    public func shouldPrompt(_ i: Inputs) -> Bool {
        // Hard stops.
        if i.optedOut || i.isSupporter { return false }
        if i.promptedThisSession { return false }
        // Engagement gates — never on the very first session.
        guard i.sessionCount >= minSessions else { return false }
        guard i.workoutsCompleted >= minWorkouts else { return false }
        // Snooze after a previous prompt: BOTH the time and launch gate must pass.
        if let last = i.lastPromptAt {
            let daysSince = i.now.timeIntervalSince(last) / 86_400
            if daysSince < snoozeDays { return false }
            if i.launchesSinceLastPrompt < snoozeLaunches { return false }
        }
        return true
    }
}
