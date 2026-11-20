import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchMesocycleMirrorTests {
    private func settings(now: Date) -> WatchMesocycleMirror.CoachSettings {
        WatchMesocycleMirror.CoachSettings(
            trainingGoal: .hypertrophy,
            experience: .intermediate,
            preferredStyle: .fitness,
            schedule: .default,
            trackedGroups: [.chest],
            preferredSetsPerExercise: 3,
            unit: .kilograms,
            warmupMinutes: 5,
            cooldownMinutes: 5,
            engineContext: SuggestedWorkoutEngineContext(asOf: now),
            excludedCardioTypes: [],
            excludedHIITProtocolIDs: [],
            weeklyCardioTargetMinutes: WeeklyCardioProgress.target)
    }

    private func candidate(id: String, name: String, muscle: String) -> SuggestedExerciseCandidate {
        SuggestedExerciseCandidate(
            id: id,
            name: name,
            mechanics: .compound,
            primaryMuscles: [muscle],
            isPersonalized: true)
    }

    private func mirror(now: Date) -> WatchMesocycleMirror {
        let bench = candidate(id: "bench", name: "Bench Press", muscle: "chest")
        let session = WatchMesocycleMirror.StrengthSession(
            id: UUID(),
            date: now.addingTimeInterval(-3600),
            endedAt: now.addingTimeInterval(-1800),
            sets: (0..<3).map { _ in
                WatchMesocycleMirror.StrengthSet(
                    exerciseID: bench.id, exerciseName: bench.name,
                    reps: 8, weightKg: 60)
            })
        return WatchMesocycleMirror(
            generatedAt: now,
            coachSettings: settings(now: now),
            allTimeWorkoutCount: 1,
            allTimeWorkingSetCount: 3,
            recentlyCompletedCandidateIDs: ["bench"],
            mostRecentExerciseWorkingSets: 3,
            strengthSessions: [session],
            exercises: [bench.id: .init(id: bench.id, name: bench.name,
                                       primaryMuscles: bench.primaryMuscles,
                                       secondaryMuscles: [], volumeEligible: true)],
            candidates: [bench],
            cardioSessions: [
                .init(id: UUID(), type: .run, durationMinutes: 30,
                      moderateEquivalentMinutes: 30, intensity: .moderate,
                      isInterval: false, isIndoor: false, start: now.addingTimeInterval(-7200))
            ])
    }

    @Test func codecRoundTripPreservesTheMirror() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = WatchMesocycleEnvelope(
            revision: WatchMesocycleHash.make(try PropertyListEncoder().encode(mirror(now: now))),
            mirror: mirror(now: now))
        let decoded = try #require(WatchMesocycleCodec.decode(try WatchMesocycleCodec.encode(envelope)))
        #expect(decoded == envelope)
    }

    @Test func newerRevisionWinsAndOlderIsIgnored() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let suite = FileManager.default.temporaryDirectory
            .appendingPathComponent("mesocycle-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: suite) }
        let store = WatchMesocycleMirrorStore(url: suite)
        let first = WatchMesocycleEnvelope(revision: "first", mirror: mirror(now: now))
        let newer = WatchMesocycleEnvelope(revision: "newer", mirror: mirror(now: now.addingTimeInterval(60)))
        let older = WatchMesocycleEnvelope(revision: "older", mirror: mirror(now: now.addingTimeInterval(-60)))
        #expect(store.apply(first))
        #expect(store.apply(newer))
        #expect(store.load()?.revision == "newer")
        #expect(!store.apply(older))
        #expect(store.load()?.revision == "newer")
        #expect(!store.apply(newer))
    }

    @Test func strengthInputUsesTheMirroredWeekAndLatestSession() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let mirror = mirror(now: now)
        let request = try #require(WatchMesocycleInputBuilder.strengthRequest(from: mirror, now: now))
        #expect(request.unit == .kilograms)
        #expect(request.input.completedSetsByMuscle["chest"] == 3)
        #expect(request.input.historyWorkoutCount == 1)
        #expect(request.input.historyWorkingSetCount == 3)
        #expect(request.input.recentlyCompletedCandidateIDs == ["bench"])
        #expect(request.input.mostRecentExerciseWorkingSets == 3)
    }

    @Test func cardioInputUsesTheMirroredWeekAndSettings() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let mirror = mirror(now: now)
        let input = WatchMesocycleInputBuilder.cardioInput(from: mirror, now: now)
        #expect(input.weeklyModerateEquivalentMinutes == 30)
        #expect(input.weeklyTargetMinutes == WeeklyCardioProgress.target)
        #expect(input.experience == .intermediate)
        #expect(input.history.count == 1)
        #expect(WatchMesocycleInputBuilder.cardioSuggestion(from: mirror, now: now) != nil)
    }

    @Test func activeWorkoutAllocationExcludesItsExercises() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let bench = candidate(id: "bench", name: "Bench Press", muscle: "chest")
        let row = candidate(id: "row", name: "Barbell Row", muscle: "lats")
        var coach = settings(now: now)
        coach.trackedGroups = [.chest, .lats]
        let mirror = WatchMesocycleMirror(
            generatedAt: now,
            coachSettings: coach,
            allTimeWorkoutCount: 0,
            allTimeWorkingSetCount: 0,
            strengthSessions: [],
            exercises: [:],
            candidates: [bench, row],
            cardioSessions: [])
        let input = WatchMesocycleInputBuilder.strengthInput(
            from: mirror,
            activeExerciseNames: ["Bench Press"],
            activeWorkingSets: (0..<3).map { _ in
                WatchSuggestionSet(exerciseName: "Bench Press")
            },
            now: now)
        #expect(input?.candidates.map(\.id) == ["row"])
        #expect(input?.completedSetsByMuscle["chest"] == 3)
    }

    @Test func emptyHistoryStillProducesAValidStarterSuggestionFromCandidates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let bench = candidate(id: "bench", name: "Bench Press", muscle: "chest")
        let mirror = WatchMesocycleMirror(
            generatedAt: now,
            coachSettings: settings(now: now),
            allTimeWorkoutCount: 0,
            allTimeWorkingSetCount: 0,
            strengthSessions: [],
            exercises: [:],
            candidates: [bench],
            cardioSessions: [])
        let request = WatchMesocycleInputBuilder.strengthRequest(from: mirror, now: now)
        #expect(request?.input.completedSetsByMuscle.isEmpty == true)
        #expect(request?.input.candidates == [bench])
    }
}
