import XCTest
import CadenceFeatures

final class CuePolicyTests: XCTestCase {
    func testPersonalBestReplacesSetCue() {
        let policy = CuePolicy()
        XCTAssertEqual(policy.cue(for: .loggedSet(isPersonalBest: true)), .personalBest)
        XCTAssertEqual(policy.cue(for: .loggedSet(isPersonalBest: false)), .setLogged)
    }

    func testQuietKeepsHapticCuesButOffSuppressesCelebrations() {
        XCTAssertEqual(CuePolicy(celebrationStyle: .quiet).cue(for: .dayCompleted), .dayClosed)
        XCTAssertNil(CuePolicy(celebrationStyle: .off).cue(for: .dayCompleted))
        XCTAssertEqual(CuePolicy(celebrationStyle: .off).cue(for: .restFinished), .restDone)
    }

    func testRestEndingOnlyFiresForFinalThreeSeconds() {
        let policy = CuePolicy()
        XCTAssertNil(policy.cue(for: .rest(secondsRemaining: 4)))
        XCTAssertEqual(policy.cue(for: .rest(secondsRemaining: 3)), .restEnding)
    }
}
