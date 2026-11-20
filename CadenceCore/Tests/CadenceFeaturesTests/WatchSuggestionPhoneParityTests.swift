#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

/// Fixture-level phone ↔ Watch parity: the phone resolves `SuggestedWorkoutGenerator
/// .suggestSingleExercise` from the same store inputs the request factory uses; the
/// Watch resolves it from the production 12-week mirror seam through the session.
@MainActor
struct WatchSuggestionPhoneParityTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func store() throws -> ModelContext {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
        return context
    }

    private func settings() -> AppSettings {
        // In-memory settings keep the parity fixtures free of UserDefaults /
        // preferences-daemon IPC while still exercising the real AppSettings type.
        AppSettings(storage: InMemoryDefaultsStore())
    }

    @discardableResult
    private func log(_ name: String, muscle: String, daysAgo: Double, in context: ModelContext) throws -> WorkoutSession {
        let date = now.addingTimeInterval(-86_400 * daysAgo)
        let s = try WorkoutRepository.createSession(date: date, in: context)
        let e = try WorkoutRepository.findOrCreateExercise(named: name, primaryMuscles: [muscle], in: context)
        for i in 0..<3 {
            _ = try WorkoutRepository.addSet(to: s, exercise: e, weightKg: 60, reps: 8,
                                             completedAt: date.addingTimeInterval(Double(i) * 60), in: context)
        }
        s.endedAt = date.addingTimeInterval(600)
        return s
    }

    /// Phone side: same inputs as `SuggestedExerciseRequestFactory.make`.
    private func phoneInput(_ context: ModelContext, _ settings: AppSettings) throws -> SuggestedWorkoutInput {
        let history = try WorkoutRepository.allSessions(context).filter { $0.countsAsStrengthHistory }
        let sets = history.reduce(0) { $0 + $1.completedOwnerWorkingSetCount }
        let keys = try ExerciseHistoryIndexStore.personalizedExerciseKeys(sessions: history, storageURL: nil)
        let exercises = try WorkoutRepository.allExercises(context)
        let persisted = exercises.map {
            SuggestedExerciseCandidate(
                id: ExerciseSuggestionExclusionKey.forExercise($0), name: $0.name,
                mechanics: $0.mechanicsValue ?? .compound, primaryMuscles: $0.primaryMuscles,
                secondaryMuscles: $0.secondaryMuscles, equipment: $0.equipmentValue,
                volumeEligible: $0.volumeEligible, trainingTypes: $0.trainingTypes,
                modalities: $0.modalities, sportContexts: $0.sportContexts,
                isPersonalized: keys.contains(ExerciseSuggestionExclusionKey.forExercise($0)))
        }
        let candidates = SuggestedExerciseFilter.excluding(
            persisted, keys: try ExerciseSuggestionExclusionStore.activeKeys(in: context))
        let facts = TrainingFacts.make(sessions: history, now: now, goal: settings.trainingGoal,
                                       experience: settings.experienceLevel)
        let schedule = settings.coachSchedulePreferences
        return SuggestedWorkoutInput(
            completedSetsByMuscle: facts.weeklySetsByMuscle, candidates: candidates,
            historyData: sets > 0 ? TrainingEngineBridge.historyData(from: history, subjectId: "cladiron-local") : nil,
            historyWorkoutCount: history.filter { $0.completedOwnerWorkingSetCount > 0 }.count,
            historyWorkingSetCount: sets,
            recentlyCompletedCandidateIDs: RecentSuggestionExclusion.candidateIDs(
                sessions: history, candidates: candidates),
            trackedGroups: schedule.trackedMuscleGroups,
            preferredSetsPerExercise: schedule.desiredSetsPerExercise,
            mostRecentExerciseWorkingSets: RecentSuggestionExclusion.mostRecentExerciseSetCount(sessions: history),
            trainingGoal: settings.trainingGoal, preferredStyle: settings.preferredWorkoutStyle,
            engineContext: SuggestedWorkoutEngineContext(
                experience: settings.experienceLevel, schedule: schedule,
                availableEquipment: Equipment.allCases, environment: "commercial_gym", asOf: now))
    }

    /// Watch side: build the production 12-week mirror from the same store and
    /// settings. `historyIndexStorageURL: nil` keeps the fixture hermetic.
    private func watchMirror(_ context: ModelContext,
                             _ settings: AppSettings) throws -> WatchMesocycleMirror {
        try WatchMesocycleMirrorBuilder.make(
            context: context, settings: settings, now: now,
            historyIndexStorageURL: nil)
    }

    private func watchInput(_ mirror: WatchMesocycleMirror, active: [String] = [],
                            transient: Set<String> = []) throws -> SuggestedWorkoutInput {
        try #require(WatchMesocycleInputBuilder.strengthInput(
            from: mirror,
            activeExerciseNames: active,
            activeWorkingSets: active.map { WatchSuggestionSet(exerciseName: $0) },
            transientExcludedCandidateIDs: transient,
            now: now))
    }

    private func watchResult(_ input: SuggestedWorkoutInput) async -> WatchSingleExerciseSuggestionSession.State {
        let session = WatchSingleExerciseSuggestionSession()
        session.suggest(input: input)
        await session.pendingTask?.value
        return session.state
    }

    private func assertSame(_ phone: SuggestedWorkoutExercise?, _ state: WatchSingleExerciseSuggestionSession.State,
                            sourceLocation: SourceLocation = #_sourceLocation) {
        guard let phone else {
            #expect(state == .empty, sourceLocation: sourceLocation); return
        }
        guard case .ready(let w) = state else {
            Issue.record("Watch not ready: \(state)", sourceLocation: sourceLocation)
            return
        }
        #expect(w.candidateID == phone.candidateID, sourceLocation: sourceLocation)
        #expect(w.plannedSets == phone.plannedSets, sourceLocation: sourceLocation)
        #expect(w.repRange == phone.repRange, sourceLocation: sourceLocation)
    }

    @Test func noHistoryMatches() async throws {
        let context = try store(), s = settings()
        let phoneIn = try phoneInput(context, s)
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(input: phoneIn, style: phoneIn.preferredStyle)
        #expect(phone != nil)
        assertSame(phone, await watchResult(try watchInput(try watchMirror(context, s))))
    }

    @Test func enoughHistoryMatches() async throws {
        let context = try store(), s = settings()
        for (i, n) in ["Bench Press", "Overhead Press", "Barbell Row", "Squat"].enumerated() {
            try log(n, muscle: ["chest", "shoulders", "lats", "quadriceps"][i], daysAgo: Double(i + 1) * 2, in: context)
        }
        let phoneIn = try phoneInput(context, s)
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(input: phoneIn, style: phoneIn.preferredStyle)
        assertSame(phone, await watchResult(try watchInput(try watchMirror(context, s))))
    }

    @Test func currentWorkoutContainingBestCandidateIsExcludedByBoth() async throws {
        let context = try store(), s = settings()
        try log("Bench Press", muscle: "chest", daysAgo: 4, in: context)
        let phoneIn = try phoneInput(context, s)
        let first = try #require(SuggestedWorkoutGenerator.suggestSingleExercise(
            input: phoneIn, style: phoneIn.preferredStyle))
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(
            input: phoneIn, style: phoneIn.preferredStyle, excludingCandidateIDs: [first.candidateID])
        let mirror = try watchMirror(context, s)
        let active = [first.name]
        let state = await watchResult(try watchInput(mirror, active: active))
        #expect(phone?.candidateID != first.candidateID)
        guard case .ready(let w) = state else {
            Issue.record("\(state)")
            return
        }
        #expect(w.candidateID != first.candidateID)
        #expect(w.candidateID == phone?.candidateID)
        #expect(w.plannedSets == phone?.plannedSets)
        #expect(w.repRange == phone?.repRange)
    }

    @Test func suggestAnotherExcludesOnlyFirstAndMatches() async throws {
        let context = try store(), s = settings()
        try log("Bench Press", muscle: "chest", daysAgo: 3, in: context)
        let phoneIn = try phoneInput(context, s)
        let first = try #require(SuggestedWorkoutGenerator.suggestSingleExercise(
            input: phoneIn, style: phoneIn.preferredStyle))
        let phoneNext = SuggestedWorkoutGenerator.suggestSingleExercise(
            input: phoneIn, style: phoneIn.preferredStyle, excludingCandidateIDs: [first.candidateID])
        let mirror = try watchMirror(context, s)
        let session = WatchSingleExerciseSuggestionSession()
        let input = try watchInput(mirror)
        session.suggest(input: input)
        await session.pendingTask?.value
        assertSame(first, session.state)
        session.suggestAnother(input: input)
        await session.pendingTask?.value
        assertSame(phoneNext, session.state)
    }

    @Test func permanentExclusionHonoredByBoth() async throws {
        let context = try store(), s = settings()
        try log("Bench Press", muscle: "chest", daysAgo: 3, in: context)
        let before = try phoneInput(context, s)
        let top = try #require(SuggestedWorkoutGenerator.suggestSingleExercise(
            input: before, style: before.preferredStyle))
        let exercise = try #require(WorkoutRepository.allExercises(context).first {
            ExerciseSuggestionExclusionKey.forExercise($0) == top.candidateID })
        try ExerciseSuggestionExclusionStore.setExcluded(exercise: exercise, reason: .personalPreference, in: context)
        let phoneIn = try phoneInput(context, s)
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(input: phoneIn, style: phoneIn.preferredStyle)
        #expect(phone?.candidateID != top.candidateID)
        assertSame(phone, await watchResult(try watchInput(try watchMirror(context, s))))
    }

    /// The 12-week mirror must reproduce the phone's Personalized input and
    /// output exactly, including candidates, weekly volume, counts, recent
    /// exclusions, set count, and the generated movements.
    @Test func watchMirrorMatchesThePhonePersonalizedPlan() async throws {
        let context = try store(), s = settings()
        for (i, n) in ["Bench Press", "Overhead Press", "Barbell Row", "Squat"].enumerated() {
            try log(n, muscle: ["chest", "shoulders", "lats", "quadriceps"][i], daysAgo: Double(i + 1) * 2, in: context)
        }
        let phoneIn = try phoneInput(context, s)
        let mirror = try watchMirror(context, s)
        let request = try #require(WatchMesocycleInputBuilder.strengthRequest(from: mirror, now: now))
        let watchIn = request.input
        #expect(watchIn.completedSetsByMuscle == phoneIn.completedSetsByMuscle)
        #expect(watchIn.candidates.map(\.id) == phoneIn.candidates.map(\.id))
        #expect(watchIn.historyWorkoutCount == phoneIn.historyWorkoutCount)
        #expect(watchIn.historyWorkingSetCount == phoneIn.historyWorkingSetCount)
        #expect(watchIn.recentlyCompletedCandidateIDs == phoneIn.recentlyCompletedCandidateIDs)
        #expect(watchIn.mostRecentExerciseWorkingSets == phoneIn.mostRecentExerciseWorkingSets)
        #expect(watchIn.trackedGroups == phoneIn.trackedGroups)
        #expect(watchIn.trainingGoal == phoneIn.trainingGoal)
        #expect(watchIn.preferredStyle == phoneIn.preferredStyle)

        let phoneOption = SuggestedWorkoutGenerator.generatePersonalized(input: phoneIn)
        let watchOption = try #require(CoachSuggestionService.generate(
            from: CoachSuggestionSnapshotBuilder.make(request: request, generatedAt: mirror.generatedAt)))
        #expect(watchOption.exercises.map(\.candidateID) == phoneOption.exercises.map(\.candidateID))
        #expect(watchOption.exercises.map(\.plannedSets) == phoneOption.exercises.map(\.plannedSets))
        #expect(watchOption.exercises.map(\.repRange) == phoneOption.exercises.map(\.repRange))
    }

    @Test func completedWorkoutChangingWeeklyVolumeMatchesNextSync() async throws {
        let context = try store(), s = settings()
        try log("Bench Press", muscle: "chest", daysAgo: 6, in: context)
        let stale = try watchMirror(context, s)
        for d in [1.0, 2.0] { try log("Bench Press", muscle: "chest", daysAgo: d, in: context) }
        let fresh = try watchMirror(context, s)
        let staleIn = try #require(WatchMesocycleInputBuilder.strengthRequest(from: stale, now: now)?.input)
        let freshIn = try #require(WatchMesocycleInputBuilder.strengthRequest(from: fresh, now: now)?.input)
        #expect(staleIn.completedSetsByMuscle != freshIn.completedSetsByMuscle)
        let phoneIn = try phoneInput(context, s)
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(input: phoneIn, style: phoneIn.preferredStyle)
        #expect(freshIn.completedSetsByMuscle == phoneIn.completedSetsByMuscle)
        assertSame(phone, await watchResult(try watchInput(fresh)))
    }

    @Test func cachedMirrorSurvivesRelaunchWithoutPhone() async throws {
        let context = try store(), s = settings()
        try log("Bench Press", muscle: "chest", daysAgo: 3, in: context)
        let phoneIn = try phoneInput(context, s)
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(input: phoneIn, style: phoneIn.preferredStyle)
        let storage = InMemoryWatchMesocycleMirrorStorage()
        let first = WatchMesocycleMirrorStore(storage: storage)
        let envelope = WatchMesocycleEnvelope(revision: "rev-1", mirror: try watchMirror(context, s))
        #expect(first.apply(envelope))
        // "Relaunch": a new store instance reads only the persisted storage.
        let reopened = try #require(WatchMesocycleMirrorStore(storage: storage).load())
        #expect(reopened == envelope)
        assertSame(phone, await watchResult(try watchInput(reopened.mirror)))
    }

    @Test func buildIsDeterministicAndOffMain() async throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let seed = ModelContext(container)
        for i in 0..<30 { try log("Bench Press", muscle: "chest", daysAgo: Double(i + 1), in: seed) }
        try seed.save()
        let now = self.now
        let (a, b, onMain) = try await Task.detached { () -> (WatchMesocycleMirror, WatchMesocycleMirror, Bool) in
            let c = ModelContext(container)
            let settings = AppSettings(storage: InMemoryDefaultsStore())
            let x = try WatchMesocycleMirrorBuilder.make(
                context: c, settings: settings, now: now, historyIndexStorageURL: nil)
            let y = try WatchMesocycleMirrorBuilder.make(
                context: c, settings: settings, now: now, historyIndexStorageURL: nil)
            return (x, y, pthread_main_np() != 0)
        }.value
        #expect(!onMain)
        #expect(a == b, "unchanged inputs must produce an identical mirror (no revision churn)")
        #expect(a.candidates.count <= WatchMesocycleMirror.maxCandidates)
    }
}
#endif
