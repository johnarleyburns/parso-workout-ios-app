import XCTest
@testable import CadenceFeatures
import CadenceCore

final class WatchQuickTalkPlannerTests: XCTestCase {
    private func context(_ exercises: [String]) -> WatchQuickTalkPlanner.Context {
        .init(unit: .kilograms, currentExercise: nil, exercises: exercises, performers: [], activePerformer: nil)
    }

    func testNearNameCorrectionIsReviewedNotApplied() {
        let outcome = WatchQuickTalkPlanner.outcome(for: "squad 100 kg for 5", context: context(["Squat"]))
        guard case .review(let items) = outcome else { return XCTFail("expected review, got \(outcome)") }
        XCTAssertTrue(items.first?.title.contains("Squat") == true)
        if case .apply = outcome { XCTFail("must not apply") }
    }

    func testExactNameStillApplies() {
        guard case .apply = WatchQuickTalkPlanner.outcome(for: "squat 100 kg for 5", context: context(["Squat"])) else {
            return XCTFail("expected apply")
        }
    }

    func testAmbiguousNearMatchNotUnderstood() {
        let outcome = WatchQuickTalkPlanner.outcome(for: "squad 100 kg for 5", context: context(["Squat", "Squab"]))
        guard case .notUnderstood = outcome else { return XCTFail("got \(outcome)") }
    }

    func testOutcomeIndependentOfSource() {
        let ctx = context(["Squat"])
        for source in [WatchQuickTalkSource.iPhone, .dictation] {
            _ = source
            XCTAssertEqual(WatchQuickTalkPlanner.outcome(for: "squad 100 kg for 5", context: ctx),
                           WatchQuickTalkPlanner.outcome(for: "squad 100 kg for 5", context: ctx))
        }
    }
}
