#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

final class WatchStrengthSyncApplierTests {
    private nonisolated(unsafe) var container: ModelContainer!
    private nonisolated(unsafe) var context: ModelContext!

    init() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    deinit {
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

    @Test func policyDecisions() {
        let a = series(5), b = series(10)
        #expect(HRCompletionPolicy.decide(existing: b, incoming: [], incomingFinal: nil, appliedFinal: nil) == .keepExisting)
        #expect(HRCompletionPolicy.decide(existing: b, incoming: a, incomingFinal: 1, appliedFinal: 2) == .rejectStale)
        #expect(HRCompletionPolicy.decide(existing: a, incoming: b, incomingFinal: nil, appliedFinal: nil) == .replace(b))
        #expect(HRCompletionPolicy.decide(existing: b, incoming: a, incomingFinal: nil, appliedFinal: nil) == .keepExisting)
    }

    @Test func emptyCompletionKeepsDenseSeriesAndDuplicateIsIdempotent() throws {
        let id = UUID()
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(20), final: 20), in: context)
        let session = try #require(fetchSessions().first { $0.id == id })
        let stored = session.hrSamplePoints
        #expect(stored.count == 20)
        let summary = session.intensitySummaryData

        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: nil), in: context)
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: [], final: 25), in: context)
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(20), final: 20), in: context)
        #expect(session.hrSamplePoints == stored)
        #expect(session.intensitySummaryData == summary)
        #expect(!session.hrCompletionPending)
    }

    @Test func heartRateFinalizedNotificationPostsOnlyOnReplacement() throws {
        let id = UUID()
        var posts = 0
        let token = NotificationCenter.default.addObserver(forName: .workoutHeartRateFinalized, object: nil, queue: nil) { if ($0.object as? UUID) == id { posts += 1 } }
        defer { NotificationCenter.default.removeObserver(token) }
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(5)), in: context)
        #expect(posts == 1)
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(5)), in: context)  // duplicate
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(3)), in: context)  // keep
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: nil), in: context)
        #expect(posts == 1)
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(10), final: 4), in: context)
        #expect(posts == 2)
        // Stale by real sequence, though it has more samples than the sequence suggests.
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(12), final: 3), in: context)
        #expect(posts == 2)
        let session = try #require(fetchSessions().first { $0.id == id })
        #expect(session.hrSamplePoints.count == 10)
        #expect(session.hrAppliedFinalSequence == 4)
    }

    @Test func staleFinalSequenceAndLargerSeries() throws {
        let id = UUID()
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(10), final: 5), in: context)
        let session = try #require(fetchSessions().first { $0.id == id })
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(30), final: 3), in: context)
        #expect(session.hrSamplePoints.count == 10)
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(30), final: 9), in: context)
        #expect(session.hrSamplePoints.count == 30)
        #expect(session.hrAppliedFinalSequence == 9)
    }

    @Test func malformedPayloadDoesNotCorruptAndMarksPending() throws {
        let id = UUID()
        var bad = endPayload(id, samples: nil)
        bad["hr_samples"] = [1.0, 2.0, 3.0]
        try WatchStrengthSyncApplier.apply(userInfo: bad, in: context)
        let session = try #require(fetchSessions().first { $0.id == id })
        #expect(session.hrSamplePoints.isEmpty)
        #expect(session.hrCompletionPending)
        try WatchStrengthSyncApplier.apply(userInfo: endPayload(id, samples: series(10), final: 1), in: context)
        bad["hr_samples"] = [Double](repeating: 1, count: WatchStrengthHeartRate.maximumTransportDoubles + 2)
        try WatchStrengthSyncApplier.apply(userInfo: bad, in: context)
        #expect(session.hrSamplePoints.count == 10)
        #expect(!session.hrCompletionPending)
    }

    @Test func endSessionBeforeLogSetCreatesFinalizedNonResumableSession() throws {
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

        let session = try #require(fetchSessions().first { $0.id == sessionID })
        #expect(session.endedAt == endedAt)
        #expect(!session.isResumable)
        #expect(session.orderedSets.count == 1)
        #expect(session.orderedSets.first?.rpe == 8)
    }

    @Test func logSetStoresIncomingSetIDSoReplayIsIgnored() throws {
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

        let session = try #require(fetchSessions().first { $0.id == sessionID })
        #expect(first == .logSet)
        #expect(second == .ignored)
        #expect(session.orderedSets.count == 1)
        #expect(session.orderedSets.first?.id == setID)
    }

    @Test func endSessionAppliesRichPlanPayloadToMirroredSession() throws {
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

        let session = try #require(fetchSessions().first { $0.id == sessionID })
        #expect(session.planSessionID == sessionID)
        #expect(session.plannedPrescriptions.first?.sourceItemID == sourceItemID)
        #expect(session.plannedPrescriptions.first?.sets.first?.restSeconds == 150)
    }

    @Test func endSessionTransmitsWatchHeartRateAndSummarizesZones() throws {
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

        let session = try #require(fetchSessions().first { $0.id == sessionID })
        #expect(session.hrSamplePoints == samples)
        let summary = try #require(session.intensitySummary)
        #expect(summary.vigorousDuration > 0)
        #expect(!summary.zoneDurations.isEmpty)
        let data = WorkoutSummaryData.from(session: session)
        #expect(data.hr.count == samples.count)
        #expect(data.cardioIntensity == summary)
    }

    @Test func strengthHeartRateCountsTowardWeeklyCardioMinutes() throws {
        let session = WorkoutSession(title: "Lift", date: Date())
        context.insert(session)
        let profile = CardioIntensityProfile(restingHR: 60, maximumHR: 190, maximumHRSource: .userEntered)
        session.recordHeartRate((0..<10).map { HRSamplePoint(t: Double($0) * 60, bpm: 130) }, profile: profile)
        let weekly = WeeklyCardioAggregator.summarize([], since: Date().addingTimeInterval(-86_400),
                                                      profile: profile, sessions: [session])
        #expect(weekly.moderateEquivalentMinutes > 0)
        #expect(!weekly.zoneMinutes.isEmpty)
        let none = WeeklyCardioAggregator.summarize([], since: Date().addingTimeInterval(-86_400),
                                                    profile: profile, sessions: [WorkoutSession(title: "No HR")])
        #expect(none.moderateEquivalentMinutes == 0)
    }

    // MARK: - Shared resolved profile (issue #546)

    private func profile6317() -> CardioIntensityProfile {
        CardioIntensityProfile(restingHR: 63, maximumHR: 173, maximumHRSource: .userEntered)
    }

    private func watchEnd(_ id: UUID, _ samples: [HRSamplePoint]) -> [String: Any] {
        ["action": "end_session", "session_id": id.uuidString, "ended_at": 2_000.0,
         WatchStrengthHeartRate.transportKey: WatchStrengthHeartRate.encode(samples)]
    }

    private func denseSamples() -> [HRSamplePoint] {
        (0..<40).map { HRSamplePoint(t: Double($0) * 30, bpm: $0 < 20 ? 111 : 130) }
    }

    @Test func watchEndImportMatchesAccumulatorForResolvedProfile() throws {
        let id = UUID()
        let samples = denseSamples()
        let profile = profile6317()
        try WatchStrengthSyncApplier.apply(userInfo: watchEnd(id, samples), in: context, intensityProfile: profile)
        let session = try #require(fetchSessions().first { $0.id == id })
        let expected = CardioMinuteAccumulator.summarize(
            duration: max(session.duration, samples.map(\.t).max() ?? 0), samples: samples, profile: profile)
        let got = try #require(session.intensitySummary)
        #expect(got == expected)
        #expect(got.moderateDuration > 0)
        #expect(got.vigorousDuration > 0)
    }

    @MainActor
    @Test func lateObservationFinalizationMatchesNormalWatchImport() throws {
        let samples = denseSamples()
        let profile = profile6317()
        let id = UUID()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let pre = WorkoutSession(title: "Strength", date: base)
        pre.id = id
        context.insert(pre)
        var payload = watchEnd(id, samples)
        payload["ended_at"] = base.addingTimeInterval(1_200).timeIntervalSince1970
        try WatchStrengthSyncApplier.apply(userInfo: payload, in: context, intensityProfile: profile)
        let normal = try #require(fetchSessions().first { $0.id == id })

        let late = WorkoutSession(title: "Strength", date: base)
        late.endedAt = normal.endedAt
        context.insert(late)
        let recorder = PhoneStrengthHeartRateRecorder(session: late, save: { try self.context.save() })
        for s in samples {
            recorder.record(HeartRateObservation(source: .watchHealthKit,
                                                 observedAt: base.addingTimeInterval(s.t), bpm: s.bpm), now: base)
        }
        #expect(recorder.finalize(profile: profile))
        let lateSummary = try #require(late.intensitySummary)
        let normalSummary = try #require(normal.intensitySummary)
        #expect(normalSummary.moderateDuration > 0)
        #expect(normalSummary.vigorousDuration > 0)
        #expect(abs(lateSummary.moderateDuration - normalSummary.moderateDuration) <= 0.001)
        #expect(abs(lateSummary.vigorousDuration - normalSummary.vigorousDuration) <= 0.001)
    }

    @Test func watchImportWithoutCachedProfileUsesPercentMaxFallback() throws {
        let id = UUID()
        let fallback = CardioIntensityProfile.resolved(userEnteredMaximumHR: nil, age: 35)
        try WatchStrengthSyncApplier.apply(userInfo: watchEnd(id, denseSamples()), in: context,
                                           intensityProfile: fallback)
        let session = try #require(fetchSessions().first { $0.id == id })
        #expect(session.intensitySummary != nil)
        #expect(session.hrSamplePoints.count == 40)
    }

    @MainActor
    @Test func lateFinalizationDoesNotOverwriteManualCardioMinutes() throws {
        let base = Date()
        let session = WorkoutSession(title: "Strength", date: base)
        session.endedAt = base.addingTimeInterval(2_000)
        context.insert(session)
        session.setManualCardioMinutes(moderate: 12, vigorous: 3)
        let manual = session.intensitySummary
        let recorder = PhoneStrengthHeartRateRecorder(session: session, save: { try self.context.save() })
        for s in denseSamples() {
            recorder.record(HeartRateObservation(source: .watchHealthKit,
                                                 observedAt: base.addingTimeInterval(s.t), bpm: s.bpm), now: base)
        }
        #expect(recorder.finalize(profile: profile6317()))
        #expect(session.hasManualCardioMinutesOverride)
        #expect(session.intensitySummary == manual)
    }

    @Test func deleteSetPayloadRemovesMirroredSet() throws {
        let session = try WorkoutRepository.createSession(title: "Strength", in: context)
        let exercise = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: context)
        let set = try WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: 80, reps: 8, in: context)

        let action = try WatchStrengthSyncApplier.apply(userInfo: [
            "action": "delete_set",
            "session_id": session.id.uuidString,
            "set_id": set.id.uuidString,
        ], in: context)

        #expect(action == .deleteSet)
        #expect(session.orderedSets.isEmpty)
    }

    @Test func deleteExercisePayloadRemovesSetsAndPlannedName() throws {
        let session = try WorkoutRepository.createSession(title: "Strength", in: context)
        let exercise = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: context)
        session.plannedExerciseNames = ["Bench Press"]
        _ = try WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: 80, reps: 8, in: context)

        let action = try WatchStrengthSyncApplier.apply(userInfo: [
            "action": "delete_exercise",
            "session_id": session.id.uuidString,
            "exercise": "Bench Press",
        ], in: context)

        #expect(action == .deleteExercise)
        #expect(session.orderedSets.isEmpty)
        #expect(session.plannedExerciseNames.isEmpty)
    }

    private func fetchSessions() throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>())
    }
}
#endif
