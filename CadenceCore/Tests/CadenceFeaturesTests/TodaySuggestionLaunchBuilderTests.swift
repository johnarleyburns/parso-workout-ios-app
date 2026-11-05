import XCTest
import SwiftData
@testable import CadenceCore
@testable import CadenceFeatures

final class TodaySuggestionLaunchBuilderTests: XCTestCase {
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

    func testBackgroundContextBuildsValueOnlyDeterministicSnapshot() async throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        try seed(ModelContext(container), workouts: 120)
        let snap = settings()
        let first: TodaySuggestionLaunchSnapshot = try await Task.detached {
            try Self.build(ModelContext(container), settings: snap)
        }.value
        let second: TodaySuggestionLaunchSnapshot = try await Task.detached {
            try Self.build(ModelContext(container), settings: snap)
        }.value
        XCTAssertTrue(first.hasMinimumHistory)
        XCTAssertEqual(first.request?.input.historyWorkoutCount, 120)
        XCTAssertEqual(first.request?.input.historyWorkingSetCount, 720)
        XCTAssertEqual(first, second)
    }

    func testKeySensitivityAndActiveSessionExclusion() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        try seed(context, workouts: 4)
        let base = try Self.build(context, settings: settings())
        XCTAssertEqual(base.earlyKey, try Self.build(context, settings: settings()).earlyKey)
        XCTAssertNotEqual(base.earlyKey, try Self.build(context, settings: settings(unit: .pounds)).earlyKey)
        XCTAssertNotEqual(base.earlyKey, try Self.build(context, settings: settings(warmup: 9)).earlyKey)
        let active = try WorkoutRepository.allSessions(context)[0].id
        XCTAssertNotEqual(base.earlyKey, try Self.build(context, active: active, settings: settings()).earlyKey)
        context.insert(Exercise(name: "Custom Curl"))
        try context.save()
        XCTAssertNotEqual(base.earlyKey, try Self.build(context, settings: settings()).earlyKey)
    }

    func testZeroHistoryBuildsStarterRequest() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let snap = try Self.build(context, settings: settings())
        XCTAssertTrue(snap.hasMinimumHistory)
        XCTAssertNotNil(snap.request)
    }

    func testTooLittleHistoryHasNoRequest() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        try seed(context, workouts: 1)
        let snap = try Self.build(context, settings: settings())
        XCTAssertFalse(snap.hasMinimumHistory)
        XCTAssertNil(snap.request)
    }
}
