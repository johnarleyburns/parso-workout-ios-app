import Foundation
import Testing
@testable import CadenceCore

struct ContributionPromptEngineTests {
    private let engine = ContributionPromptEngine()
    // A fixed reference time so the snooze cases never flirt with wall-clock or
    // midnight boundaries (unlike the date-relative recovery suites).
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    /// A fully-eligible baseline: enough workouts + sessions, not a supporter, not
    /// opted out, not yet prompted this session, never prompted before.
    private func eligible() -> ContributionPromptEngine.Inputs {
        .init(workoutsCompleted: 10, sessionCount: 3, isSupporter: false, optedOut: false,
              promptedThisSession: false, lastPromptAt: nil, launchesSinceLastPrompt: 0, now: now)
    }

    @Test func promptsWhenFullyEligible() {
        #expect(engine.shouldPrompt(eligible()))
    }

    @Test func neverOnFirstSession() {
        var i = eligible(); i.sessionCount = 1
        #expect(!engine.shouldPrompt(i), "first session must never prompt")
    }

    @Test func requiresEnoughWorkouts() {
        var i = eligible(); i.workoutsCompleted = 5
        #expect(!engine.shouldPrompt(i), "below minWorkouts must not prompt")
        i.workoutsCompleted = 6
        #expect(engine.shouldPrompt(i), "exactly minWorkouts qualifies")
    }

    @Test func neverWhenOptedOut() {
        var i = eligible(); i.optedOut = true
        #expect(!engine.shouldPrompt(i))
    }

    @Test func neverWhenAlreadySupporter() {
        var i = eligible(); i.isSupporter = true
        #expect(!engine.shouldPrompt(i))
    }

    @Test func atMostOncePerSession() {
        var i = eligible(); i.promptedThisSession = true
        #expect(!engine.shouldPrompt(i))
    }

    @Test func snoozeNeedsBothTimeAndLaunches() {
        var i = eligible()
        // Prompted 3 days ago, only 6 launches: time gate fails (need 7 days).
        i.lastPromptAt = now.addingTimeInterval(-3 * 86_400)
        i.launchesSinceLastPrompt = 6
        #expect(!engine.shouldPrompt(i), "under the day gate → no re-prompt")

        // 8 days ago but only 2 launches: launch gate fails (need 5).
        i.lastPromptAt = now.addingTimeInterval(-8 * 86_400)
        i.launchesSinceLastPrompt = 2
        #expect(!engine.shouldPrompt(i), "under the launch gate → no re-prompt")

        // 8 days ago AND 6 launches: both gates pass → re-prompt.
        i.launchesSinceLastPrompt = 6
        #expect(engine.shouldPrompt(i), "both snooze gates cleared → prompt again")
    }
}
