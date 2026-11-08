import XCTest
@testable import CadenceCore
@testable import CadenceFeatures

final class CoachWatchTodayBridgeTests: XCTestCase {
    private func session(_ id: String, _ payload: CoachSession.LaunchPayload,
                         exercises: [CoachSession.RecommendedExercise]? = nil) -> CoachSession {
        CoachSession(id: id, kind: .moderateAerobic, title: "Boxing conditioning", subtitle: "",
                     durationMinutes: 25, exercises: exercises, modality: nil, intensity: nil,
                     trainingLoadTags: [], citationIds: [], launchPayload: payload,
                     systemsTrained: [], evidenceCategory: nil)
    }

    func testCardioSuggestionProjectsToWatch() throws {
        let s = try XCTUnwrap(CoachWatchTodayBridge.watchSession(
            from: session("box", .cardio(type: "boxing", durationMinutes: 25))))
        XCTAssertEqual(s.kind, .cardio)
        XCTAssertEqual(s.label, "Boxing conditioning")
        XCTAssertEqual(s.cardioType, "boxing")
        XCTAssertEqual(s.durationMinutes, 25)
    }

    func testStrengthSuggestionCarriesExerciseNames() throws {
        let s = try XCTUnwrap(CoachWatchTodayBridge.watchSession(
            from: session("str", .strengthPlan("p"), exercises: [.init(name: "Bench Press")])))
        XCTAssertEqual(s.kind, .strength)
        XCTAssertEqual(s.exerciseNames, ["Bench Press"])
    }

    func testAssessmentIsNotProjected() {
        XCTAssertNil(CoachWatchTodayBridge.watchSession(from: session("a", .assessment)))
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

    func testBothModalitiesEmittedWithoutTwoADays() {
        let plan = CoachWatchTodayBridge.todayPlan(from: decision(strength: true, cardio: true))
        XCTAssertEqual(plan.sessions.map(\.kind), [.strength, .cardio])
        XCTAssertEqual(plan.sessions.map(\.isCompanionRecommendation), [false, true])
    }

    func testGeneratedStrengthKeepsCardioSibling() throws {
        let editable = EditablePlan(title: "Upper", warmupMinutes: 0, cooldownMinutes: 0, exercises: [
            EditableExercise(name: "Bench Press",
                             sets: [EditableSet(targetReps: 5, targetWeight: 60)], notes: "")])
        let plan = CoachWatchTodayBridge.todayPlan(from: decision(strength: true, cardio: true),
                                                   suggestedStrength: editable)
        XCTAssertEqual(plan.sessions.map(\.kind), [.strength, .cardio])
        XCTAssertEqual(plan.sessions[0].id, "today-suggested-strength")
        XCTAssertEqual(plan.sessions[0].planPayload?.strength?.prescriptions.count, 1)
    }

    func testCompletedModalitiesAreOmitted() {
        XCTAssertEqual(CoachWatchTodayBridge.todayPlan(from: decision(strength: false, cardio: true)).sessions.map(\.kind), [.cardio])
        XCTAssertEqual(CoachWatchTodayBridge.todayPlan(from: decision(strength: true, cardio: false)).sessions.map(\.kind), [.strength])
        XCTAssertTrue(CoachWatchTodayBridge.todayPlan(from: decision(strength: false, cardio: false)).sessions.isEmpty)
    }

    func testCompanionMetadataRoundTripsAndDefaultsWhenAbsent() throws {
        let plan = CoachWatchTodayBridge.todayPlan(from: decision(strength: true, cardio: true))
        let ctx = WatchSync.TodayPlan.contextDict(plan)
        let decoded = try XCTUnwrap(WatchSync.TodayPlan.from(context: ctx))
        XCTAssertEqual(decoded.sessions.map(\.isCompanionRecommendation), [false, true])
        var rows = try XCTUnwrap(ctx[WatchSync.Key.todayPlanSessions] as? [[String: Any]])
        rows[1].removeValue(forKey: "isCompanionRecommendation")
        XCTAssertFalse(WatchSync.TodayPlan.sessions(fromRows: rows)[1].isCompanionRecommendation)
    }
}
