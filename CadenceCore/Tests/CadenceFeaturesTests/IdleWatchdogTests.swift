import XCTest
import CadenceFeatures

/// Launch-blockers Phase 1a: the idle watchdog may prompt and auto-pause, but
/// auto-end is unrepresentable — `TickResult` has no end case, so no sequence
/// of ticks can ever end a workout.
final class IdleWatchdogTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testPromptAppearsAfterTimeout() {
        var dog = IdleWatchdog(now: t0)
        XCTAssertEqual(dog.tick(now: t0.addingTimeInterval(9 * 60), timeoutMinutes: 10,
                                isPaused: false, enabled: true), .none)
        XCTAssertEqual(dog.tick(now: t0.addingTimeInterval(10 * 60), timeoutMinutes: 10,
                                isPaused: false, enabled: true), .showPrompt)
    }

    func testIgnoredPromptAutoPausesNeverEnds() {
        var dog = IdleWatchdog(now: t0)
        let promptAt = t0.addingTimeInterval(10 * 60)
        XCTAssertEqual(dog.tick(now: promptAt, timeoutMinutes: 10, isPaused: false, enabled: true),
                       .showPrompt)
        // Within the 30s grace: nothing.
        XCTAssertEqual(dog.tick(now: promptAt.addingTimeInterval(29), timeoutMinutes: 10,
                                isPaused: false, enabled: true), .none)
        // Grace expires → auto-PAUSE (the only automatic action that exists).
        XCTAssertEqual(dog.tick(now: promptAt.addingTimeInterval(30), timeoutMinutes: 10,
                                isPaused: false, enabled: true), .autoPause)
        // Long after (10 min, 24 h): still nothing — no end case exists to fire.
        XCTAssertEqual(dog.tick(now: promptAt.addingTimeInterval(10 * 60), timeoutMinutes: 10,
                                isPaused: false, enabled: true), .none)
        XCTAssertEqual(dog.tick(now: promptAt.addingTimeInterval(24 * 3600), timeoutMinutes: 10,
                                isPaused: false, enabled: true), .none)
        XCTAssertEqual(dog.state, .autoPaused)
    }

    func testAnyActivityResetsAndClearsPrompt() {
        var dog = IdleWatchdog(now: t0)
        let promptAt = t0.addingTimeInterval(10 * 60)
        XCTAssertEqual(dog.tick(now: promptAt, timeoutMinutes: 10, isPaused: false, enabled: true),
                       .showPrompt)
        dog.recordActivity(now: promptAt.addingTimeInterval(5))
        XCTAssertEqual(dog.state, .idle(lastActivity: promptAt.addingTimeInterval(5)))
        // Fresh activity restarts the full timeout.
        XCTAssertEqual(dog.tick(now: promptAt.addingTimeInterval(6), timeoutMinutes: 10,
                                isPaused: false, enabled: true), .none)
    }

    func testActivityClearsAutoPausedState() {
        var dog = IdleWatchdog(now: t0)
        _ = dog.tick(now: t0.addingTimeInterval(600), timeoutMinutes: 10, isPaused: false, enabled: true)
        _ = dog.tick(now: t0.addingTimeInterval(631), timeoutMinutes: 10, isPaused: false, enabled: true)
        XCTAssertEqual(dog.state, .autoPaused)
        let resumeAt = t0.addingTimeInterval(700)
        dog.recordActivity(now: resumeAt)
        XCTAssertEqual(dog.state, .idle(lastActivity: resumeAt))
    }

    func testForegroundingCountsAsActivity() {
        // Locking the phone for longer than timeout+grace, then unlocking:
        // scenePhase == .active records activity BEFORE the next tick, so the
        // user sees no prompt and no pause after a normal lock/unlock.
        var dog = IdleWatchdog(now: t0)
        let unlockAt = t0.addingTimeInterval(45 * 60)
        dog.recordActivity(now: unlockAt)   // scenePhase → .active
        XCTAssertEqual(dog.tick(now: unlockAt.addingTimeInterval(1), timeoutMinutes: 10,
                                isPaused: false, enabled: true), .none)
    }

    func testPausedNeverPrompts() {
        var dog = IdleWatchdog(now: t0)
        XCTAssertEqual(dog.tick(now: t0.addingTimeInterval(3600), timeoutMinutes: 10,
                                isPaused: true, enabled: true), .none)
        XCTAssertEqual(dog.state, .idle(lastActivity: t0))
    }

    func testDisabledNeverPrompts() {
        var dog = IdleWatchdog(now: t0)
        XCTAssertEqual(dog.tick(now: t0.addingTimeInterval(3600), timeoutMinutes: 10,
                                isPaused: false, enabled: false), .none)
        XCTAssertEqual(dog.state, .idle(lastActivity: t0))
    }
}
