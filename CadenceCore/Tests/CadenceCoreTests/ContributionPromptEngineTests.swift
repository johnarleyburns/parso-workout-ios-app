import XCTest
@testable import CadenceCore

final class ContributionPromptEngineTests: XCTestCase {
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

    func testPromptsWhenFullyEligible() {
        XCTAssertTrue(engine.shouldPrompt(eligible()))
    }

    func testNeverOnFirstSession() {
        var i = eligible(); i.sessionCount = 1
        XCTAssertFalse(engine.shouldPrompt(i), "first session must never prompt")
    }

    func testRequiresEnoughWorkouts() {
        var i = eligible(); i.workoutsCompleted = 5
        XCTAssertFalse(engine.shouldPrompt(i), "below minWorkouts must not prompt")
        i.workoutsCompleted = 6
        XCTAssertTrue(engine.shouldPrompt(i), "exactly minWorkouts qualifies")
    }

    func testNeverWhenOptedOut() {
        var i = eligible(); i.optedOut = true
        XCTAssertFalse(engine.shouldPrompt(i))
    }

    func testNeverWhenAlreadySupporter() {
        var i = eligible(); i.isSupporter = true
        XCTAssertFalse(engine.shouldPrompt(i))
    }

    func testAtMostOncePerSession() {
        var i = eligible(); i.promptedThisSession = true
        XCTAssertFalse(engine.shouldPrompt(i))
    }

    func testSnoozeNeedsBothTimeAndLaunches() {
        var i = eligible()
        // Prompted 3 days ago, only 6 launches: time gate fails (need 7 days).
        i.lastPromptAt = now.addingTimeInterval(-3 * 86_400)
        i.launchesSinceLastPrompt = 6
        XCTAssertFalse(engine.shouldPrompt(i), "under the day gate → no re-prompt")

        // 8 days ago but only 2 launches: launch gate fails (need 5).
        i.lastPromptAt = now.addingTimeInterval(-8 * 86_400)
        i.launchesSinceLastPrompt = 2
        XCTAssertFalse(engine.shouldPrompt(i), "under the launch gate → no re-prompt")

        // 8 days ago AND 6 launches: both gates pass → re-prompt.
        i.launchesSinceLastPrompt = 6
        XCTAssertTrue(engine.shouldPrompt(i), "both snooze gates cleared → prompt again")
    }
}
