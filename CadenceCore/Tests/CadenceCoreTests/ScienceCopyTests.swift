import Testing
@testable import CadenceCore

struct ScienceCopyTests {

    @Test func starterDoesNotClaimOvertrainingDiagnosis() {
        let starter = KnowledgeBase.starter(goal: .strength, experience: .beginner)
        #expect(!starter.detail.contains("overtrained"))
        #expect(!starter.detail.contains("overtraining"))
        #expect(!starter.action.contains("overtrained"))
    }

    @Test func deloadDoesNotClaimOvertrainingDiagnosis() {
        let snap = LiftSnapshot(exercise: "Squat", group: .quadriceps,
                                 topSetWeightKg: 100, topSetReps: 5, bestE1RM: 100, trend: .declining)
        let facts = TrainingFacts(weeklySetsByGroup: [:], frequencyByGroup: [:],
                                   e1RMTrendByExercise: [:], intensity: .empty, avgRPE: nil,
                                   daysSinceLastSession: nil, totalWorkingSets: 5,
                                   liftSnapshots: ["Squat": snap],
                                   goal: .strength, experience: .intermediate)
        let recs = KnowledgeBase.deload.produce(facts)
        for r in recs {
            #expect(!r.detail.contains("overtrained"), "Deload detail for \(r.id) mentions overtraining")
            #expect(!r.detail.contains("overtraining"), "Deload detail for \(r.id) mentions overtraining")
            #expect(!r.title.contains("overtrained"))
        }
    }

    @Test func cardioModerateDoesNotCall150MinOptimal() {
        let facts = TrainingFacts(weeklySetsByGroup: [:], frequencyByGroup: [:],
                                   e1RMTrendByExercise: [:], intensity: .empty, avgRPE: nil,
                                   daysSinceLastSession: nil, totalWorkingSets: 1,
                                   goal: .strength, experience: .beginner)
        let recs = KnowledgeBase.cardioModerate.produce(facts)
        for r in recs {
            #expect(!r.detail.contains("optimal"), "Cardio detail for \(r.id) calls 150min optimal")
        }
    }

    @Test func recommendationEngineAllOutputsCited() {
        let snap = LiftSnapshot(exercise: "Squat", group: .quadriceps,
                                 topSetWeightKg: 100, topSetReps: 4, bestE1RM: 100, trend: .flat)
        let facts = TrainingFacts(weeklySetsByGroup: [.chest: 2], frequencyByGroup: [:],
                                   e1RMTrendByExercise: [:], intensity: .empty, avgRPE: nil,
                                   daysSinceLastSession: nil, totalWorkingSets: 5,
                                   liftSnapshots: ["Squat": snap],
                                   goal: .strength, experience: .intermediate)
        let known = Set(CitationRegistry.all.map(\.id))
        let recs = RecommendationEngine.run(facts)
        for rec in recs {
            #expect(known.contains(rec.citation.id),
                          "Recommendation \(rec.id) cites unknown citation \(rec.citation.id)")
        }
    }

    @Test func coachDecisionWarningsAreCited() {
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate)
        let decision = CoachDecisionEngine.run(facts)
        let known = Set(CitationRegistry.all.map(\.id))
        for w in decision.warnings {
            for cid in w.citationIds {
                #expect(known.contains(cid), "Warning \(w.id) cites unknown citation \(cid)")
            }
        }
    }
}
