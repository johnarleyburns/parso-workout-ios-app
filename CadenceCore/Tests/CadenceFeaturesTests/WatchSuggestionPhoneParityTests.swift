import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

/// Fixture-level phone ↔ Watch parity: the phone resolves `SuggestedWorkoutGenerator
/// .suggestSingleExercise` from the same store inputs the request factory uses; the
/// Watch resolves it from a JSON round-tripped context through the session.
@MainActor
final class WatchSuggestionPhoneParityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func store() throws -> ModelContext {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
        return context
    }

    private func settings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "wspp-\(UUID().uuidString)")!)
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

    /// Watch side: build, JSON round-trip (as transported), assemble.
    private func watchContext(_ context: ModelContext, _ settings: AppSettings) throws -> WatchSingleExerciseSuggestionContext {
        let built = try WatchSingleExerciseSuggestionContextBuilder.make(
            context: context, settings: settings, now: now, historyIndexStorageURL: nil)
        let data = try XCTUnwrap(built.propertyListValue)
        return try XCTUnwrap(WatchSingleExerciseSuggestionContext.decodePayload(data))
    }

    private func watchInput(_ ctx: WatchSingleExerciseSuggestionContext, active: [String] = [],
                            transient: Set<String> = []) throws -> SuggestedWorkoutInput {
        try XCTUnwrap(WatchSingleExerciseSuggestionAssembler.make(
            context: ctx, activeExerciseNames: active,
            activeWorkingSets: active.map { WatchSuggestionSet(exerciseName: $0) },
            transientExcludedCandidateIDs: transient))
    }

    private func watchResult(_ input: SuggestedWorkoutInput) async -> WatchSingleExerciseSuggestionSession.State {
        let session = WatchSingleExerciseSuggestionSession()
        session.suggest(input: input)
        await session.pendingTask?.value
        return session.state
    }

    private func assertSame(_ phone: SuggestedWorkoutExercise?, _ state: WatchSingleExerciseSuggestionSession.State,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let phone else {
            XCTAssertEqual(state, .empty, file: file, line: line); return
        }
        guard case .ready(let w) = state else { return XCTFail("Watch not ready: \(state)", file: file, line: line) }
        XCTAssertEqual(w.candidateID, phone.candidateID, file: file, line: line)
        XCTAssertEqual(w.plannedSets, phone.plannedSets, file: file, line: line)
        XCTAssertEqual(w.repRange, phone.repRange, file: file, line: line)
    }

    func testNoHistoryMatches() async throws {
        let context = try store(), s = settings()
        let phoneIn = try phoneInput(context, s)
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(input: phoneIn, style: phoneIn.preferredStyle)
        XCTAssertNotNil(phone)
        assertSame(phone, await watchResult(try watchInput(try watchContext(context, s))))
    }

    func testEnoughHistoryMatches() async throws {
        let context = try store(), s = settings()
        for (i, n) in ["Bench Press", "Overhead Press", "Barbell Row", "Squat"].enumerated() {
            try log(n, muscle: ["chest", "shoulders", "lats", "quadriceps"][i], daysAgo: Double(i + 1) * 2, in: context)
        }
        let phoneIn = try phoneInput(context, s)
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(input: phoneIn, style: phoneIn.preferredStyle)
        assertSame(phone, await watchResult(try watchInput(try watchContext(context, s))))
    }

    func testCurrentWorkoutContainingBestCandidateIsExcludedByBoth() async throws {
        let context = try store(), s = settings()
        try log("Bench Press", muscle: "chest", daysAgo: 4, in: context)
        let phoneIn = try phoneInput(context, s)
        let first = try XCTUnwrap(SuggestedWorkoutGenerator.suggestSingleExercise(
            input: phoneIn, style: phoneIn.preferredStyle))
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(
            input: phoneIn, style: phoneIn.preferredStyle, excludingCandidateIDs: [first.candidateID])
        let ctx = try watchContext(context, s)
        let active = [first.name]
        let state = await watchResult(try watchInput(ctx, active: active))
        XCTAssertNotEqual(phone?.candidateID, first.candidateID)
        guard case .ready(let w) = state else { return XCTFail("\(state)") }
        XCTAssertNotEqual(w.candidateID, first.candidateID)
        XCTAssertEqual(w.candidateID, phone?.candidateID)
        XCTAssertEqual(w.plannedSets, phone?.plannedSets)
        XCTAssertEqual(w.repRange, phone?.repRange)
    }

    func testSuggestAnotherExcludesOnlyFirstAndMatches() async throws {
        let context = try store(), s = settings()
        try log("Bench Press", muscle: "chest", daysAgo: 3, in: context)
        let phoneIn = try phoneInput(context, s)
        let first = try XCTUnwrap(SuggestedWorkoutGenerator.suggestSingleExercise(
            input: phoneIn, style: phoneIn.preferredStyle))
        let phoneNext = SuggestedWorkoutGenerator.suggestSingleExercise(
            input: phoneIn, style: phoneIn.preferredStyle, excludingCandidateIDs: [first.candidateID])
        let ctx = try watchContext(context, s)
        let session = WatchSingleExerciseSuggestionSession()
        let input = try watchInput(ctx)
        session.suggest(input: input)
        await session.pendingTask?.value
        assertSame(first, session.state)
        session.suggestAnother(input: input)
        await session.pendingTask?.value
        assertSame(phoneNext, session.state)
    }

    func testPermanentExclusionHonoredByBoth() async throws {
        let context = try store(), s = settings()
        try log("Bench Press", muscle: "chest", daysAgo: 3, in: context)
        let before = try phoneInput(context, s)
        let top = try XCTUnwrap(SuggestedWorkoutGenerator.suggestSingleExercise(
            input: before, style: before.preferredStyle))
        let exercise = try XCTUnwrap(WorkoutRepository.allExercises(context).first {
            ExerciseSuggestionExclusionKey.forExercise($0) == top.candidateID })
        try ExerciseSuggestionExclusionStore.setExcluded(exercise: exercise, reason: .personalPreference, in: context)
        let phoneIn = try phoneInput(context, s)
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(input: phoneIn, style: phoneIn.preferredStyle)
        XCTAssertNotEqual(phone?.candidateID, top.candidateID)
        assertSame(phone, await watchResult(try watchInput(try watchContext(context, s))))
    }

    func testCompletedWorkoutChangingWeeklyVolumeMatchesNextSync() async throws {
        let context = try store(), s = settings()
        try log("Bench Press", muscle: "chest", daysAgo: 6, in: context)
        let stale = try watchContext(context, s)
        for d in [1.0, 2.0] { try log("Bench Press", muscle: "chest", daysAgo: d, in: context) }
        let fresh = try watchContext(context, s)
        XCTAssertNotEqual(stale.baseInput.completedSetsByMuscle, fresh.baseInput.completedSetsByMuscle)
        let phoneIn = try phoneInput(context, s)
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(input: phoneIn, style: phoneIn.preferredStyle)
        XCTAssertEqual(try watchInput(fresh).completedSetsByMuscle, phoneIn.completedSetsByMuscle)
        assertSame(phone, await watchResult(try watchInput(fresh)))
    }

    func testCachedContextSurvivesRelaunchWithoutPhone() async throws {
        let context = try store(), s = settings()
        try log("Bench Press", muscle: "chest", daysAgo: 3, in: context)
        let phoneIn = try phoneInput(context, s)
        let phone = SuggestedWorkoutGenerator.suggestSingleExercise(input: phoneIn, style: phoneIn.preferredStyle)
        let suite = UserDefaults(suiteName: "wspp-store-\(UUID().uuidString)")!
        let first = WatchSingleExerciseSuggestionContextStore(defaults: suite)
        XCTAssertEqual(first.replace(try watchContext(context, s)), .replaced)
        // "Relaunch": a new store instance reads only the persisted defaults.
        let reopened = try XCTUnwrap(WatchSingleExerciseSuggestionContextStore(defaults: suite).load())
        assertSame(phone, await watchResult(try watchInput(reopened)))
    }

    func testBuildIsBoundedDeterministicAndOffMain() async throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let seed = ModelContext(container)
        for i in 0..<30 { try log("Bench Press", muscle: "chest", daysAgo: Double(i + 1), in: seed) }
        try seed.save()
        let start = Date()
        let now = self.now
        let (a, b, onMain) = try await Task.detached { () -> (WatchSingleExerciseSuggestionContext, WatchSingleExerciseSuggestionContext, Bool) in
            let c = ModelContext(container)
            let settings = AppSettings(defaults: UserDefaults(suiteName: "wspp-bg-\(UUID().uuidString)")!)
            let x = try WatchSingleExerciseSuggestionContextBuilder.make(
                context: c, settings: settings, now: now, historyIndexStorageURL: nil)
            let y = try WatchSingleExerciseSuggestionContextBuilder.make(
                context: c, settings: settings, now: now, historyIndexStorageURL: nil)
            return (x, y, pthread_main_np() != 0)
        }.value
        XCTAssertFalse(onMain)
        XCTAssertEqual(a, b, "unchanged inputs must produce an identical context (no revision churn)")
        XCTAssertLessThanOrEqual(a.baseInput.candidates.count, WatchSingleExerciseSuggestionContextBuilder.maxCandidates)
        XCTAssertLessThan(Date().timeIntervalSince(start), 30)
    }
}
