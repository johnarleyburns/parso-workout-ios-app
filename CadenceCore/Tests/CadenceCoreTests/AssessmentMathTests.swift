import XCTest
@testable import CadenceCore

/// strength-pivot P4 — pure assessment math: summaries, MDC trend, re-test cadence.
final class AssessmentMathTests: XCTestCase {

    private let day: TimeInterval = 86_400

    private func a(_ kind: AssessmentKind, _ value: Double, daysAgo: Double,
                   lift: String? = nil, now: Date = Date()) -> Assessment {
        Assessment(date: now.addingTimeInterval(-daysAgo * day),
                   kind: kind, value: value, exerciseName: lift)
    }

    // MARK: summaries / grouping

    func testGroupsByKindAndPicksBaselineLatestBest() {
        let now = Date()
        let rows = [
            a(.pushupMax, 20, daysAgo: 60, now: now),  // baseline (oldest)
            a(.pushupMax, 35, daysAgo: 30, now: now),  // best
            a(.pushupMax, 30, daysAgo: 1, now: now),   // latest
        ]
        let summaries = AssessmentMath.summaries(from: rows)
        XCTAssertEqual(summaries.count, 1)
        let s = summaries[0]
        XCTAssertEqual(s.kind, .pushupMax)
        XCTAssertEqual(s.baseline, 20)
        XCTAssertEqual(s.latest, 30)
        XCTAssertEqual(s.best, 35)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.delta, 10)
    }

    func testLiftSpecificKindsGroupPerLift() {
        let rows = [
            a(.e1RM, 100, daysAgo: 30, lift: "Bench"),
            a(.e1RM, 110, daysAgo: 1, lift: "Bench"),
            a(.e1RM, 150, daysAgo: 1, lift: "Squat"),
        ]
        let summaries = AssessmentMath.summaries(from: rows)
        XCTAssertEqual(summaries.count, 2)
        XCTAssertNotNil(summaries.first { $0.exerciseName == "Bench" })
        XCTAssertNotNil(summaries.first { $0.exerciseName == "Squat" })
    }

    func testEmptyInputYieldsNoSummaries() {
        XCTAssertTrue(AssessmentMath.summaries(from: []).isEmpty)
    }

    // MARK: MDC trend

    func testSinglePointIsSingleTrend() {
        let s = AssessmentMath.summaries(from: [a(.plankHold, 60, daysAgo: 1)])[0]
        XCTAssertEqual(s.trend, .single)
    }

    func testSmallRepChangeWithinNoiseIsUnchanged() {
        // 20 → 21 push-ups: under the max(1, 10%) = 2-rep MDC.
        let rows = [a(.pushupMax, 20, daysAgo: 40), a(.pushupMax, 21, daysAgo: 1)]
        XCTAssertEqual(AssessmentMath.summaries(from: rows)[0].trend, .unchanged)
    }

    func testClearRepGainIsImproved() {
        let rows = [a(.pushupMax, 20, daysAgo: 40), a(.pushupMax, 30, daysAgo: 1)]
        XCTAssertEqual(AssessmentMath.summaries(from: rows)[0].trend, .improved)
    }

    func testClearDeclineIsDeclined() {
        let rows = [a(.plankHold, 90, daysAgo: 40), a(.plankHold, 60, daysAgo: 1)]
        XCTAssertEqual(AssessmentMath.summaries(from: rows)[0].trend, .declined)
    }

    func testStrengthMDCIsThreePercentFloorOne() {
        // 100 kg baseline → 3 kg MDC. +2 kg is noise, +4 kg is real.
        XCTAssertEqual(AssessmentMath.minimalDetectableChange(for: .e1RM, baseline: 100), 3, accuracy: 0.001)
        let noise = [a(.e1RM, 100, daysAgo: 40, lift: "B"), a(.e1RM, 102, daysAgo: 1, lift: "B")]
        XCTAssertEqual(AssessmentMath.summaries(from: noise)[0].trend, .unchanged)
        let real = [a(.e1RM, 100, daysAgo: 40, lift: "B"), a(.e1RM, 104, daysAgo: 1, lift: "B")]
        XCTAssertEqual(AssessmentMath.summaries(from: real)[0].trend, .improved)
    }

    // MARK: re-test cadence

    func testRetestDueAfterSixWeeks() {
        let now = Date()
        let recent = AssessmentMath.summaries(from: [a(.pushupMax, 20, daysAgo: 10, now: now)])[0]
        let stale = AssessmentMath.summaries(from: [a(.pushupMax, 20, daysAgo: 50, now: now)])[0]
        XCTAssertFalse(AssessmentMath.isRetestDue(recent, now: now))
        XCTAssertTrue(AssessmentMath.isRetestDue(stale, now: now))
    }

    // MARK: e1RM passthrough

    func testE1RMUsesWorkoutMath() {
        XCTAssertEqual(AssessmentMath.e1RM(weight: 100, reps: 1), 100, accuracy: 0.001)
        XCTAssertEqual(AssessmentMath.e1RM(weight: 100, reps: 5, formula: .epley),
                       WorkoutMath.epley1RM(weight: 100, reps: 5), accuracy: 0.001)
    }
}
