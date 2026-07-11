import XCTest
@testable import CadenceCore

/// P3 (issue 11) — the coach must surface a "run this fitness test" card, at most
/// once a week, prioritizing never-tested kinds, honoring "not right now" snoozes
/// and "pick a different test" cycling.
final class CoachTestRecommendationEngineTests: XCTestCase {

    private func now() -> Date { Date(timeIntervalSince1970: 1_782_300_000) }

    private func summary(_ kind: AssessmentKind, daysAgo: Int, now: Date, count: Int = 1) -> AssessmentSummary {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return AssessmentSummary(
            kind: kind, exerciseName: kind.concernsLift ? "Back Squat" : nil,
            latest: 100, latestDate: date,
            baseline: 100, baselineDate: date,
            best: 100, count: count)
    }

    // MARK: never-tested prioritized first

    func testNeverTestedKindsPrioritized() {
        let n = now()
        // pushupMax tested recently; everything else never tested.
        let inputs = CoachTestRecommendationEngine.Inputs(
            battery: [.pushupMax, .e1RM, .plankHold],
            summaries: [summary(.pushupMax, daysAgo: 2, now: n)],
            now: n)
        let rec = CoachTestRecommendationEngine.recommendation(inputs)
        XCTAssertNotNil(rec)
        // e1RM is the first never-tested kind in battery order.
        XCTAssertEqual(rec?.kind, .e1RM)
        XCTAssertEqual(rec?.reason, .neverTested)
    }

    // MARK: only one per week

    func testOnlyOnePerWeekGate() {
        let n = now()
        let inputs = CoachTestRecommendationEngine.Inputs(
            battery: [.e1RM],
            summaries: [],
            lastRecommendedAt: Calendar.current.date(byAdding: .day, value: -3, to: n),
            now: n)
        XCTAssertNil(CoachTestRecommendationEngine.recommendation(inputs),
                     "Within 7 days of the last recommendation, none should surface")

        let older = CoachTestRecommendationEngine.Inputs(
            battery: [.e1RM],
            summaries: [],
            lastRecommendedAt: Calendar.current.date(byAdding: .day, value: -8, to: n),
            now: n)
        XCTAssertNotNil(CoachTestRecommendationEngine.recommendation(older),
                        "After 7 days a recommendation may surface again")
    }

    // MARK: "not right now" suppresses for a week

    func testSnoozeSuppressesKind() {
        let n = now()
        let snoozeUntil = Calendar.current.date(byAdding: .day, value: 5, to: n)!
        let inputs = CoachTestRecommendationEngine.Inputs(
            battery: [.e1RM, .plankHold],
            summaries: [],
            snoozedUntil: [AssessmentKind.e1RM.rawValue: snoozeUntil],
            now: n)
        let rec = CoachTestRecommendationEngine.recommendation(inputs)
        XCTAssertEqual(rec?.kind, .plankHold, "Snoozed e1RM is skipped for the next-priority kind")

        // After the snooze expires, e1RM is eligible again (and first in order).
        let later = Calendar.current.date(byAdding: .day, value: 6, to: n)!
        let expired = CoachTestRecommendationEngine.Inputs(
            battery: [.e1RM, .plankHold],
            summaries: [],
            snoozedUntil: [AssessmentKind.e1RM.rawValue: snoozeUntil],
            now: later)
        XCTAssertEqual(CoachTestRecommendationEngine.recommendation(expired)?.kind, .e1RM)
    }

    // MARK: "pick a different test" advances kind

    func testCandidatesCycleToNextKind() {
        let n = now()
        let inputs = CoachTestRecommendationEngine.Inputs(
            battery: [.e1RM, .plankHold, .pushupMax],
            summaries: [],
            now: n)
        let candidates = CoachTestRecommendationEngine.candidates(inputs)
        XCTAssertEqual(candidates.map(\.kind), [.e1RM, .plankHold, .pushupMax],
                       "Candidates are ordered so 'pick a different test' can advance")
    }

    // MARK: nothing when all fresh

    func testNothingWhenAllFresh() {
        let n = now()
        let fresh = [AssessmentKind.e1RM, .plankHold].map { summary($0, daysAgo: 5, now: n) }
        let inputs = CoachTestRecommendationEngine.Inputs(
            battery: [.e1RM, .plankHold],
            summaries: fresh,
            now: n)
        XCTAssertNil(CoachTestRecommendationEngine.recommendation(inputs),
                     "All kinds recently tested → nothing due")
        XCTAssertTrue(CoachTestRecommendationEngine.candidates(inputs).isEmpty)
    }

    // MARK: stale prioritized by staleness

    func testStalePrioritizedByMostStale() {
        let n = now()
        // Both stale (> 42d cadence); e1RM more stale than plankHold.
        let inputs = CoachTestRecommendationEngine.Inputs(
            battery: [.plankHold, .e1RM],
            summaries: [summary(.plankHold, daysAgo: 50, now: n),
                        summary(.e1RM, daysAgo: 90, now: n)],
            now: n)
        let rec = CoachTestRecommendationEngine.recommendation(inputs)
        XCTAssertEqual(rec?.kind, .e1RM, "Most-stale due test comes first")
        if case .stale(let days) = rec?.reason {
            XCTAssertEqual(days, 90)
        } else {
            XCTFail("Expected a stale reason")
        }
    }

    // MARK: never-tested outranks stale

    func testNeverTestedOutranksStale() {
        let n = now()
        let inputs = CoachTestRecommendationEngine.Inputs(
            battery: [.e1RM, .plankHold],
            summaries: [summary(.e1RM, daysAgo: 90, now: n)],  // e1RM stale, plank never
            now: n)
        XCTAssertEqual(CoachTestRecommendationEngine.recommendation(inputs)?.kind, .plankHold)
    }

    // MARK: HARD RULE — the surfaced card resolves a real citation

    func testRecommendationCarriesResolvableCitation() {
        let n = now()
        let inputs = CoachTestRecommendationEngine.Inputs(
            battery: [.e1RM], summaries: [], now: n)
        let rec = CoachTestRecommendationEngine.recommendation(inputs)
        let ids = rec?.citationIds ?? []
        XCTAssertFalse(ids.isEmpty, "Every test card must carry a citation")
        for id in ids {
            XCTAssertNotNil(CitationRegistry.citation(forId: id),
                            "Citation id \(id) must resolve in the registry")
        }
    }
}
