#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadencePhoneFeatures
@testable import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct TodaySuggestionLaunchBuilderTests {
    private static let asOfDate = Date(timeIntervalSince1970: 1_800_000_000)
    private var asOf: Date { Self.asOfDate }

    private func settings(unit: MeasurementUnitPreference = .kilograms, warmup: Int = 5) -> TodaySuggestionSettingsSnapshot {
        TodaySuggestionSettingsSnapshot(
            unit: unit, warmupMinutes: warmup, cooldownMinutes: 3, trainingGoal: .hypertrophy,
            preferredStyle: .personalized, experience: .intermediate, formula: .epley,
            schedule: .default, historyIndexStorageURL: nil)
    }

    private func seed(_ context: ModelContext, workouts: Int) throws {
        let bench = Exercise(name: "Bench Press")
        context.insert(bench)
        for i in 0..<workouts {
            let s = WorkoutSession(title: "W\(i)", date: asOf.addingTimeInterval(Double(-i) * 86_400))
            s.endedAt = s.date.addingTimeInterval(3_600)
            context.insert(s)
            for n in 0..<6 {
                context.insert(SetEntry(weight: 60, reps: 8, order: n,
                                        completedAt: s.date, session: s, exercise: bench))
            }
        }
        try context.save()
    }

    private static func build(_ context: ModelContext, active: UUID? = nil,
                       settings: TodaySuggestionSettingsSnapshot) throws -> TodaySuggestionLaunchSnapshot {
        let sessions = try WorkoutRepository.allSessions(context)
        let exercises = try WorkoutRepository.allExercises(context)
        return try TodaySuggestionLaunchBuilder.make(
            sessions: sessions, exercises: exercises, scheduled: [], exclusions: [],
            activeSessionID: active, settings: settings, asOf: asOfDate)
    }

    @Test func backgroundContextBuildsValueOnlyDeterministicSnapshot() async throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        try seed(ModelContext(container), workouts: 120)
        let snap = settings()
        let first: TodaySuggestionLaunchSnapshot = try await Task.detached {
            try Self.build(ModelContext(container), settings: snap)
        }.value
        let second: TodaySuggestionLaunchSnapshot = try await Task.detached {
            try Self.build(ModelContext(container), settings: snap)
        }.value
        #expect(first.hasMinimumHistory)
        #expect(first.request?.input.historyWorkoutCount == 120)
        #expect(first.request?.input.historyWorkingSetCount == 720)
        #expect(first == second)
    }

    @Test func keySensitivityAndActiveSessionExclusion() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        try seed(context, workouts: 4)
        let base = try Self.build(context, settings: settings())
        #expect(base.earlyKey == try Self.build(context, settings: settings()).earlyKey)
        #expect(base.earlyKey != try Self.build(context, settings: settings(unit: .pounds)).earlyKey)
        #expect(base.earlyKey != try Self.build(context, settings: settings(warmup: 9)).earlyKey)
        let active = try WorkoutRepository.allSessions(context)[0].id
        #expect(base.earlyKey != try Self.build(context, active: active, settings: settings()).earlyKey)
        context.insert(Exercise(name: "Custom Curl"))
        try context.save()
        #expect(base.earlyKey != try Self.build(context, settings: settings()).earlyKey)
    }

    @Test func zeroHistoryBuildsStarterRequest() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let snap = try Self.build(context, settings: settings())
        #expect(snap.hasMinimumHistory)
        #expect(snap.request != nil)
    }

    @Test func tooLittleHistoryHasNoRequest() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        try seed(context, workouts: 1)
        let snap = try Self.build(context, settings: settings())
        #expect(!snap.hasMinimumHistory)
        #expect(snap.request == nil)
    }
}
#endif
