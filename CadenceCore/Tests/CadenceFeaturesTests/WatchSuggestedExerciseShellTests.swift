import XCTest
@testable import CadenceFeatures
import CadenceCore

@MainActor
final class WatchSuggestedExerciseShellTests: XCTestCase {
    func testMissingContextIsUnavailableNotARandomFallback() {
        let shell = WatchSuggestedExerciseShell(loadContext: { nil })
        XCTAssertEqual(shell.phase, .calculating)
        shell.start(activeNames: ["Bench Press"], activeWorkingSets: [])
        XCTAssertEqual(shell.phase, .unavailable)
        XCTAssertEqual(shell.session.state, .idle)
    }

    func testRetryReloadsContextAndStaysUnavailableWhileAbsent() {
        var loads = 0
        let shell = WatchSuggestedExerciseShell(loadContext: { loads += 1; return nil })
        shell.start(activeNames: [], activeWorkingSets: [])
        shell.start(activeNames: [], activeWorkingSets: [])
        XCTAssertEqual(loads, 1)
        shell.retry(activeNames: [], activeWorkingSets: [])
        XCTAssertEqual(loads, 2)
        XCTAssertEqual(shell.phase, .unavailable)
    }

    func testCopyIsStable() {
        XCTAssertEqual(WatchSuggestedExerciseShell.unavailableMessage,
                       "Suggestions are updating—sync with iPhone and try again")
        XCTAssertEqual(WatchSuggestedExerciseShell.calculatingTitle, "Finding an exercise…")
    }
}
