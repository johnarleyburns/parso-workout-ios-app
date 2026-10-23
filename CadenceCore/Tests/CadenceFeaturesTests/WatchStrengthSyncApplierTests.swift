import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

final class WatchStrengthSyncApplierTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func endPayload(_ id: UUID, samples: [HRSamplePoint]?, final: Int? = nil) -> [String: Any] {
        var p: [String: Any] = ["action": "end_session", "session_id": id.uuidString,
                                "ended_at": 2_000.0, "session_title": "Strength"]
        if let samples { p["hr_samples"] = WatchStrengthHeartRate.encode(samples) }
        if let final { p["hr_final_sequence"] = final }
        return p
    }

    private func series(_ n: Int) -> [HRSamplePoint] {
        (0..<n).map { HRSamplePoint(t: Double($0) * 5, bpm: 100 + Double($0 % 30)) }
    }

    func testPolicyDecisions() {
        let a = series(5), b = series(10)
        XCTAssertEqual(HRCompletionPolicy.decide(existing: b, incoming: [], incomingFinal: nil, appliedFinal: nil), .keepExisting)
        XCTAssertEqual(HRCompletionPolicy.decide(existing: b, incoming: a, incomingFinal: 1, appliedFinal: 2), .rejectStale)
        XCTAssertEqual(HRCompletionPolicy.decide(existing: a, incoming: b, incomingFinal: nil, appliedFinal: nil), .replace(b))
        XCTAssertEqual(HRCompletionPolicy.decide(existing: b, incoming: a, incomingFinal: nil, appliedFinal: nil), .keepExisting)
    }

    func testEmptyCompletionKeepsDenseSeriesAndDuplicateIsIdempotent() throws {
        let id = UUID()
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(20), final: 20), in: context)
        let session = try XCTUnwrap(fetchSessions().first { $0.id == id })
        let stored = session.hrSamplePoints
        XCTAssertEqual(stored.count, 20)
        let summary = session.intensitySummaryData

        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: nil), in: context)
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: [], final: 25), in: context)
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(20), final: 20), in: context)
        XCTAssertEqual(session.hrSamplePoints, stored)
        XCTAssertEqual(session.intensitySummaryData, summary)
        XCTAssertFalse(session.hrCompletionPending)
    }

    func testStaleFinalSequenceAndLargerSeries() throws {
        let id = UUID()
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(10), final: 5), in: context)
        let session = try XCTUnwrap(fetchSessions().first { $0.id == id })
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(30), final: 3), in: context)
        XCTAssertEqual(session.hrSamplePoints.count, 10)
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(30), final: 9), in: context)
        XCTAssertEqual(session.hrSamplePoints.count, 30)
        XCTAssertEqual(session.hrAppliedFinalSequence, 9)
    }

    func testMalformedPayloadDoesNotCorruptAndMarksPending() throws {
        let id = UUID()
        var bad = endPayload(id, samples: nil)
        bad["hr_samples"] = [1.0, 2.0, 3.0]
        try WatchStrengthSyncApplier.apply(userInfo: bad, in: context)
        let session = try XCTUnwrap(fetchSessions().first { $0.id == id })
        XCTAssertTrue(session.hrSamplePoints.isEmpty)
        XCTAssertTrue(session.hrCompletionPending)
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(10), final: 1), in: context)
        bad["hr_samples"] = [Double](repeating: 1, count: WatchStrengthHeartRate.maximumTransportDoubles + 2)
        try WatchStrengthSyncApplier.apply(userInfo: bad, in: context)
        XCTAssertEqual(session.hrSamplePoints.count, 10)
        XCTAssertFalse(session.hrCompletionPending)
    }

    func testEndSessionBeforeLogSetCreatesFinalizedNonResumableSession() throws {
        let sessionID = UUID()
        let endedAt = Date(timeIntervalSince1970: 2_000)

        try WatchStrengthSyncApplier.apply(userInfo: [
            "action": "end_session",
            "session_id": sessionID.uuidString,
            "ended_at": endedAt.timeIntervalSince1970,
            "session_title": "Strength",
            "planned_exercises": ["Bench Press"],
            "planned_rep_ladder": [12, 10, 8],
        ], in: context)

        try WatchStrengthSyncApplier.apply(userInfo: [
            "action": "log_set",
            "session_id": sessionID.uuidString,
            "set_id": UUID().uuidString,
            "exercise": "Bench Press",
            "weight": 80.0,
            "reps": 8,
            "rpe": 8.0,
            "session_title": "Strength",
            "planned_exercises": ["Bench Press"],
            "planned_rep_ladder": [12, 10, 8],
        ], in: context)

        let session = try XCTUnwrap(fetchSessions().first { $0.id == sessionID })
        XCTAssertEqual(session.endedAt, endedAt)
        XCTAssertFalse(session.isResumable)
        XCTAssertEqual(session.orderedSets.count, 1)
        XCTAssertEqual(session.orderedSets.first?.rpe, 8)
    }

    func testLogSetStoresIncomingSetIDSoReplayIsIgnored() throws {
        let sessionID = UUID()
        let setID = UUID()
        let payload: [String: Any] = [
            "action": "log_set",
            "session_id": sessionID.uuidString,
            "set_id": setID.uuidString,
            "exercise": "Bench Press",
            "weight": 80.0,
            "reps": 8,
        ]

        let first = try WatchStrengthSyncApplier.apply(userInfo: payload, in: context)
        let second = try WatchStrengthSyncApplier.apply(userInfo: payload, in: context)

        let session = try XCTUnwrap(fetchSessions().first { $0.id == sessionID })
        XCTAssertEqual(first, .logSet)
        XCTAssertEqual(second, .ignored)
        XCTAssertEqual(session.orderedSets.count, 1)
        XCTAssertEqual(session.orderedSets.first?.id, setID)
    }

    func testEndSessionAppliesRichPlanPayloadToMirroredSession() throws {
        let sessionID = UUID()
        let sourceItemID = UUID()
        let payload = WatchPlanPayload(
            planSessionID: sessionID,
            title: "Upper",
            strength: .init(
                exerciseNames: ["Bench Press"], repLadder: [5],
                prescriptions: [PlannedExercisePrescription(
                    sourceItemID: sourceItemID,
                    exerciseKey: "bench_press",
                    exerciseName: "Bench Press",
                    sets: [.init(targetReps: 5, targetWeightKg: 80,
                                  targetLoadMode: "absolute", restSeconds: 150)])]))

        try WatchStrengthSyncApplier.apply(userInfo: [
            "action": "end_session",
            "session_id": sessionID.uuidString,
            "ended_at": Date(timeIntervalSince1970: 2_000).timeIntervalSince1970,
            WatchPlanPayload.transportKey: payload.propertyList,
        ], in: context)

        let session = try XCTUnwrap(fetchSessions().first { $0.id == sessionID })
        XCTAssertEqual(session.planSessionID, sessionID)
        XCTAssertEqual(session.plannedPrescriptions.first?.sourceItemID, sourceItemID)
        XCTAssertEqual(session.plannedPrescriptions.first?.sets.first?.restSeconds, 150)
    }

    func testEndSessionTransmitsWatchHeartRateAndSummarizesZones() throws {
        let sessionID = UUID()
        let samples = (0..<20).map { HRSamplePoint(t: Double($0) * 30, bpm: 150) }
        let profile = CardioIntensityProfile(restingHR: 60, maximumHR: 190, maximumHRSource: .userEntered)

        // Round-trips through the same property-list encoding the Watch transfers.
        let flowPayload: [String: Any] = [
            "action": "end_session",
            "session_id": sessionID.uuidString,
            "ended_at": Date(timeIntervalSince1970: 2_000).timeIntervalSince1970,
            WatchStrengthHeartRate.transportKey: WatchStrengthHeartRate.encode(samples),
        ]
        try WatchStrengthSyncApplier.apply(userInfo: flowPayload, in: context, intensityProfile: profile)
        // Redelivery is idempotent.
        try WatchStrengthSyncApplier.apply(userInfo: flowPayload, in: context, intensityProfile: profile)

        let session = try XCTUnwrap(fetchSessions().first { $0.id == sessionID })
        XCTAssertEqual(session.hrSamplePoints, samples)
        let summary = try XCTUnwrap(session.intensitySummary)
        XCTAssertGreaterThan(summary.vigorousDuration, 0)
        XCTAssertFalse(summary.zoneDurations.isEmpty)
        let data = WorkoutSummaryData.from(session: session)
        XCTAssertEqual(data.hr.count, samples.count)
        XCTAssertEqual(data.cardioIntensity, summary)
    }

    func testStrengthHeartRateCountsTowardWeeklyCardioMinutes() throws {
        let session = WorkoutSession(title: "Lift", date: Date())
        context.insert(session)
        let profile = CardioIntensityProfile(restingHR: 60, maximumHR: 190, maximumHRSource: .userEntered)
        session.recordHeartRate((0..<10).map { HRSamplePoint(t: Double($0) * 60, bpm: 130) }, profile: profile)
        let weekly = WeeklyCardioAggregator.summarize([], since: Date().addingTimeInterval(-86_400),
                                                      profile: profile, sessions: [session])
        XCTAssertGreaterThan(weekly.moderateEquivalentMinutes, 0)
        XCTAssertFalse(weekly.zoneMinutes.isEmpty)
        let none = WeeklyCardioAggregator.summarize([], since: Date().addingTimeInterval(-86_400),
                                                    profile: profile, sessions: [WorkoutSession(title: "No HR")])
        XCTAssertEqual(none.moderateEquivalentMinutes, 0)
    }

    func testDeleteSetPayloadRemovesMirroredSet() throws {
        let session = try WorkoutRepository.createSession(title: "Strength", in: context)
        let exercise = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: context)
        let set = try WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: 80, reps: 8, in: context)

        let action = try WatchStrengthSyncApplier.apply(userInfo: [
            "action": "delete_set",
            "session_id": session.id.uuidString,
            "set_id": set.id.uuidString,
        ], in: context)

        XCTAssertEqual(action, .deleteSet)
        XCTAssertTrue(session.orderedSets.isEmpty)
    }

    func testDeleteExercisePayloadRemovesSetsAndPlannedName() throws {
        let session = try WorkoutRepository.createSession(title: "Strength", in: context)
        let exercise = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: context)
        session.plannedExerciseNames = ["Bench Press"]
        _ = try WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: 80, reps: 8, in: context)

        let action = try WatchStrengthSyncApplier.apply(userInfo: [
            "action": "delete_exercise",
            "session_id": session.id.uuidString,
            "exercise": "Bench Press",
        ], in: context)

        XCTAssertEqual(action, .deleteExercise)
        XCTAssertTrue(session.orderedSets.isEmpty)
        XCTAssertTrue(session.plannedExerciseNames.isEmpty)
    }

    private func fetchSessions() throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>())
    }
}
