import XCTest
@testable import CadenceCore

/// strength-pivot P4 — assessment-driven engine rules over `TrainingFacts`.
final class AssessmentInsightTests: XCTestCase {

    private let day: TimeInterval = 86_400

    private func a(_ kind: AssessmentKind, _ value: Double, daysAgo: Double,
                   lift: String? = nil, now: Date) -> Assessment {
        Assessment(date: now.addingTimeInterval(-daysAgo * day),
                   kind: kind, value: value, exerciseName: lift)
    }

    private func facts(_ assessments: [Assessment], now: Date) -> TrainingFacts {
        TrainingFacts.make(sessions: [], assessments: assessments, now: now,
                           goal: .hypertrophy, experience: .intermediate)
    }

    // MARK: cold-start is bypassed once an assessment exists

    func testAssessmentBreaksColdStart() {
        let now = Date()
        let f = facts([a(.pushupMax, 25, daysAgo: 2, now: now)], now: now)
        let insights = InsightEngine.run(f)
        XCTAssertFalse(insights.contains { $0.kind == .coldStart })
    }

    // MARK: progress rule

    func testImprovementProducesInfoInsight() {
        let now = Date()
        let f = facts([a(.pushupMax, 20, daysAgo: 40, now: now),
                       a(.pushupMax, 32, daysAgo: 2, now: now)], now: now)
        let i = InsightEngine.run(f).first { $0.id == "assessment.pushupMax" }
        XCTAssertEqual(i?.kind, .assessment)
        XCTAssertEqual(i?.severity, .info)
        XCTAssertTrue(i?.message.contains("+12 reps") ?? false, "got: \(i?.message ?? "nil")")
    }

    func testDeclineProducesAttentionInsight() {
        let now = Date()
        let f = facts([a(.plankHold, 120, daysAgo: 40, now: now),
                       a(.plankHold, 80, daysAgo: 2, now: now)], now: now)
        let i = InsightEngine.run(f).first { $0.id == "assessment.plankHold" }
        XCTAssertEqual(i?.severity, .attention)
    }

    func testSingleResultProducesNoProgressInsight() {
        let now = Date()
        let f = facts([a(.pushupMax, 20, daysAgo: 2, now: now)], now: now)
        XCTAssertNil(InsightEngine.run(f).first { $0.id == "assessment.pushupMax" })
    }

    // MARK: retest rule

    func testStaleSeriesTriggersRetestInsight() {
        let now = Date()
        let f = facts([a(.pushupMax, 20, daysAgo: 50, now: now)], now: now)
        let i = InsightEngine.run(f).first { $0.id == "assessment.retest.pushupMax" }
        XCTAssertEqual(i?.kind, .assessment)
        XCTAssertEqual(i?.severity, .info)
    }

    func testFreshSeriesDoesNotTriggerRetest() {
        let now = Date()
        let f = facts([a(.pushupMax, 20, daysAgo: 5, now: now)], now: now)
        XCTAssertNil(InsightEngine.run(f).first { $0.id.hasPrefix("assessment.retest") })
    }

    // MARK: D3 — assessment insights are cited from the known registry

    func testAssessmentInsightsAreCited() {
        let now = Date()
        let f = facts([a(.e1RM, 100, daysAgo: 50, lift: "Bench", now: now),
                       a(.e1RM, 112, daysAgo: 2, lift: "Bench", now: now)], now: now)
        let known = Set(CitationRegistry.all.map(\.id))
        let assessmentInsights = InsightEngine.run(f).filter { $0.kind == .assessment }
        XCTAssertFalse(assessmentInsights.isEmpty)
        for i in assessmentInsights {
            XCTAssertTrue(known.contains(i.citation.id), "\(i.id) cites unknown \(i.citation.id)")
        }
    }

    func testDeterministic() {
        let now = Date()
        let f = facts([a(.e1RM, 100, daysAgo: 50, lift: "Bench", now: now),
                       a(.e1RM, 112, daysAgo: 2, lift: "Bench", now: now)], now: now)
        XCTAssertEqual(InsightEngine.run(f).map(\.id), InsightEngine.run(f).map(\.id))
    }
}
