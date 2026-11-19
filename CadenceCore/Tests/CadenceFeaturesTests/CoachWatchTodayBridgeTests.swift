import Foundation
import Testing
@testable import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct CoachWatchTodayBridgeTests {
    private func session(_ id: String, _ payload: CoachSession.LaunchPayload,
                         exercises: [CoachSession.RecommendedExercise]? = nil) -> CoachSession {
        CoachSession(id: id, kind: .moderateAerobic, title: "Boxing conditioning", subtitle: "",
                     durationMinutes: 25, exercises: exercises, modality: nil, intensity: nil,
                     trainingLoadTags: [], citationIds: [], launchPayload: payload,
                     systemsTrained: [], evidenceCategory: nil)
    }

    @Test func cardioSuggestionProjectsToWatch() throws {
        let s = try #require(CoachWatchTodayBridge.watchSession(
            from: session("box", .cardio(type: "boxing", durationMinutes: 25))))
        #expect(s.kind == .cardio)
        #expect(s.label == "Boxing conditioning")
        #expect(s.cardioType == "boxing")
        #expect(s.durationMinutes == 25)
    }

    @Test func strengthSuggestionCarriesExerciseNames() throws {
        let s = try #require(CoachWatchTodayBridge.watchSession(
            from: session("str", .strengthPlan("p"), exercises: [.init(name: "Bench Press")])))
        #expect(s.kind == .strength)
        #expect(s.exerciseNames == ["Bench Press"])
    }

    @Test func assessmentIsNotProjected() {
        #expect(CoachWatchTodayBridge.watchSession(from: session("a", .assessment)) == nil)
    }

    // MARK: - Both daily modalities (#556)

    private func strengthSession() -> CoachSession {
        CoachSession(id: "str", kind: .strength, title: "Upper", subtitle: "",
                     durationMinutes: 45, exercises: [.init(name: "Bench Press")], modality: nil,
                     intensity: nil, trainingLoadTags: [], citationIds: [], launchPayload: .strengthPlan("p"),
                     systemsTrained: [], evidenceCategory: nil)
    }

    private func decision(strength: Bool, cardio: Bool) -> CoachDecision {
        let str = strengthSession()
        let car = session("box", .cardio(type: "boxing", durationMinutes: 25))
        var slots: [DailyRecommendationSlot] = []
        if strength { slots.append(.init(modality: .strength, session: str, isCompanion: false)) }
        if cardio { slots.append(.init(modality: .cardio, session: car, isCompanion: true)) }
        let balance = WeeklyBalance(
            strengthDays: 0, cardioDays: 0, patternsTrained: [], muscleGroupsTrained: [],
            fractionalSets: [:], moderateMinutes: 0, vigorousMinutes: 0,
            moderateEquivalentMinutes: 0, hardDays: 0, consecutiveHardDays: 0,
            vo2maxLatest: nil, vo2maxProtocol: nil, vo2maxTrend: nil,
            readinessAvailable: false, dataCompleteness: .moderate)
        return CoachDecision(id: "d", generatedAt: Date(), primary: str, weeklyBalance: balance,
                             confidence: .high, dailyRecommendationSlots: slots)
    }

    @Test func bothModalitiesEmittedWithoutTwoADays() {
        let plan = CoachWatchTodayBridge.todayPlan(from: decision(strength: true, cardio: true))
        #expect(plan.sessions.map(\.kind) == [.strength, .cardio])
        #expect(plan.sessions.map(\.isCompanionRecommendation) == [false, true])
    }

    @Test func generatedStrengthKeepsCardioSibling() throws {
        let editable = EditablePlan(title: "Upper", warmupMinutes: 0, cooldownMinutes: 0, exercises: [
            EditableExercise(name: "Bench Press",
                             sets: [EditableSet(targetReps: 5, targetWeight: 60)], notes: "")])
        let plan = CoachWatchTodayBridge.todayPlan(from: decision(strength: true, cardio: true),
                                                   suggestedStrength: editable)
        #expect(plan.sessions.map(\.kind) == [.strength, .cardio])
        #expect(plan.sessions[0].id == "today-suggested-strength")
        #expect(plan.sessions[0].planPayload?.strength?.prescriptions.count == 1)
    }

    @Test func completedModalitiesAreOmitted() {
        #expect(CoachWatchTodayBridge.todayPlan(from: decision(strength: false, cardio: true)).sessions.map(\.kind) == [.cardio])
        #expect(CoachWatchTodayBridge.todayPlan(from: decision(strength: true, cardio: false)).sessions.map(\.kind) == [.strength])
        #expect(CoachWatchTodayBridge.todayPlan(from: decision(strength: false, cardio: false)).sessions.isEmpty)
    }

    @Test func companionMetadataRoundTripsAndDefaultsWhenAbsent() throws {
        let plan = CoachWatchTodayBridge.todayPlan(from: decision(strength: true, cardio: true))
        let ctx = WatchSync.TodayPlan.contextDict(plan)
        let decoded = try #require(WatchSync.TodayPlan.from(context: ctx))
        #expect(decoded.sessions.map(\.isCompanionRecommendation) == [false, true])
        var rows = try #require(ctx[WatchSync.Key.todayPlanSessions] as? [[String: Any]])
        rows[1].removeValue(forKey: "isCompanionRecommendation")
        #expect(!WatchSync.TodayPlan.sessions(fromRows: rows)[1].isCompanionRecommendation)
    }
}
