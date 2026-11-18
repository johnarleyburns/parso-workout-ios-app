import Foundation
import Testing
@testable import CadenceCore

/// strength-pivot P4 — assessment-driven engine rules over `TrainingFacts`.
struct AssessmentInsightTests {

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

    @Test func assessmentBreaksColdStart() {
        let now = Date()
        let f = facts([a(.pushupMax, 25, daysAgo: 2, now: now)], now: now)
        let insights = InsightEngine.run(f)
        #expect(!insights.contains { $0.kind == .coldStart })
    }

    // MARK: progress rule

    @Test func improvementProducesInfoInsight() {
        let now = Date()
        let f = facts([a(.pushupMax, 20, daysAgo: 40, now: now),
                       a(.pushupMax, 32, daysAgo: 2, now: now)], now: now)
        let i = InsightEngine.run(f).first { $0.id == "assessment.pushupMax" }
        #expect(i?.kind == .assessment)
        #expect(i?.severity == .info)
        #expect(i?.message.contains("+12 reps") ?? false, "got: \(i?.message ?? "nil")")
    }

    @Test func declineProducesAttentionInsight() {
        let now = Date()
        let f = facts([a(.plankHold, 120, daysAgo: 40, now: now),
                       a(.plankHold, 80, daysAgo: 2, now: now)], now: now)
        let i = InsightEngine.run(f).first { $0.id == "assessment.plankHold" }
        #expect(i?.severity == .attention)
    }

    @Test func singleResultProducesNoProgressInsight() {
        let now = Date()
        let f = facts([a(.pushupMax, 20, daysAgo: 2, now: now)], now: now)
        #expect(InsightEngine.run(f).first { $0.id == "assessment.pushupMax" } == nil)
    }

    // MARK: retest rule

    @Test func staleSeriesTriggersRetestInsight() {
        let now = Date()
        let f = facts([a(.pushupMax, 20, daysAgo: 50, now: now)], now: now)
        let i = InsightEngine.run(f).first { $0.id == "assessment.retest.pushupMax" }
        #expect(i?.kind == .assessment)
        #expect(i?.severity == .info)
    }

    @Test func freshSeriesDoesNotTriggerRetest() {
        let now = Date()
        let f = facts([a(.pushupMax, 20, daysAgo: 5, now: now)], now: now)
        #expect(InsightEngine.run(f).first { $0.id.hasPrefix("assessment.retest") } == nil)
    }

    // MARK: D3 — assessment insights are cited from the known registry

    @Test func assessmentInsightsAreCited() {
        let now = Date()
        let f = facts([a(.e1RM, 100, daysAgo: 50, lift: "Bench", now: now),
                       a(.e1RM, 112, daysAgo: 2, lift: "Bench", now: now)], now: now)
        let known = Set(CitationRegistry.all.map(\.id))
        let assessmentInsights = InsightEngine.run(f).filter { $0.kind == .assessment }
        #expect(!assessmentInsights.isEmpty)
        for i in assessmentInsights {
            #expect(known.contains(i.citation.id), "\(i.id) cites unknown \(i.citation.id)")
        }
    }

    @Test func deterministic() {
        let now = Date()
        let f = facts([a(.e1RM, 100, daysAgo: 50, lift: "Bench", now: now),
                       a(.e1RM, 112, daysAgo: 2, lift: "Bench", now: now)], now: now)
        #expect(InsightEngine.run(f).map(\.id) == InsightEngine.run(f).map(\.id))
    }

    // MARK: P6 — cardio assessment insights

    @Test func vo2maxImprovementProducesInfoInsight() {
        let now = Date()
        let f = facts([a(.vo2maxField, 38, daysAgo: 60, now: now),
                       a(.vo2maxField, 45, daysAgo: 2, now: now)], now: now)
        let i = InsightEngine.run(f).first { $0.id == "assessment.cardio.vo2maxField" }
        #expect(i?.kind == .assessment)
        #expect(i?.severity == .info)
        #expect(i?.message.contains("+7.0 mL/kg/min") ?? false, "got: \(i?.message ?? "nil")")
    }

    @Test func vo2maxDeclineProducesAttentionInsight() {
        let now = Date()
        let f = facts([a(.vo2maxField, 45, daysAgo: 60, now: now),
                       a(.vo2maxField, 38, daysAgo: 2, now: now)], now: now)
        let i = InsightEngine.run(f).first { $0.id == "assessment.cardio.vo2maxField" }
        #expect(i?.severity == .attention)
    }

    @Test func wingateDeclineProducesAttentionInsight() {
        let now = Date()
        let f = facts([a(.wingate, 600, daysAgo: 60, now: now),
                       a(.wingate, 500, daysAgo: 2, now: now)], now: now)
        let i = InsightEngine.run(f).first { $0.id == "assessment.cardio.wingate" }
        #expect(i?.severity == .attention)
    }

    @Test func staleCardioSeriesTriggersRetest() {
        let now = Date()
        let f = facts([a(.wingate, 500, daysAgo: 50, now: now)], now: now)
        let i = InsightEngine.run(f).first { $0.id == "assessment.cardio.retest.wingate" }
        #expect(i?.kind == .assessment)
        #expect(i?.severity == .info)
    }

    @Test func cardioInsightsUseCardioCitations() {
        let now = Date()
        let f = facts([a(.vo2maxField, 38, daysAgo: 60, now: now),
                       a(.vo2maxField, 45, daysAgo: 2, now: now),
                       a(.wingate, 600, daysAgo: 60, now: now),
                       a(.wingate, 500, daysAgo: 2, now: now)], now: now)
        let insights = InsightEngine.run(f).filter { $0.id.hasPrefix("assessment.cardio") }
        for i in insights {
            let ids = Set(CitationRegistry.all.map(\.id))
            #expect(ids.contains(i.citation.id), "\(i.id) cites unknown \(i.citation.id)")
        }
    }
}
