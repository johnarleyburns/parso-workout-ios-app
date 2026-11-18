#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
struct WatchLiftSourcesTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    @Test func menuOrder() {
        #expect(WatchLiftSources.menuOrder.map(\.title) == ["Personalized", "Previous", "Custom"])
        #expect(WatchLiftSources.Source.suggest.accessibilityIdentifier == "watchStrength.suggest")
        #expect(WatchLiftSources.menuTitle == "Lift")
    }

    @discardableResult
    private func addSession(_ ctx: ModelContext, title: String, end: Date?, sets: [(String, Int)],
                            deleted: Bool = false, date: Date = Date(timeIntervalSince1970: 100)) throws -> WorkoutSession {
        let s = try WorkoutRepository.createSession(title: title, in: ctx)
        s.date = date
        s.endedAt = end
        if deleted { s.deletedAt = Date() }
        for (name, reps) in sets {
            let ex = try WorkoutRepository.findOrCreateExercise(named: name, in: ctx)
            _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 50, reps: reps, in: ctx)
        }
        try ctx.save()
        return s
    }

    @Test func previousFiltersAndOrders() throws {
        let ctx = try makeContext()
        for i in 1...6 {
            try addSession(ctx, title: "W\(i)", end: Date(timeIntervalSince1970: Double(1000 + i)),
                           sets: [("Bench Press", 8), ("Bench Press", 8), ("Row", 10)])
        }
        try addSession(ctx, title: "Deleted", end: Date(timeIntervalSince1970: 5000), sets: [("Bench Press", 8)], deleted: true)
        try addSession(ctx, title: "Open", end: nil, sets: [("Bench Press", 8)])
        try addSession(ctx, title: "Empty", end: Date(timeIntervalSince1970: 5000), sets: [])
        try addSession(ctx, title: "ZeroReps", end: Date(timeIntervalSince1970: 5000), sets: [("Bench Press", 0)])
        let list = WatchLiftSources.load(from: ctx)
        #expect(list.map(\.title) == ["W6", "W5", "W4", "W3", "W2"])
        #expect(list[0].exerciseCount == 2)
        #expect(list[0].workingSetCount == 3)
        #expect(list[0].structureLines == ["Bench Press · 2×8", "Row · 1×10"])
        #expect(list[0].launch.exerciseNames == ["Bench Press", "Row"])
    }

    @Test func previousEmptyAndFallbackOrdering() throws {
        let ctx = try makeContext()
        #expect(WatchLiftSources.load(from: ctx).isEmpty)
        try addSession(ctx, title: "", end: Date(timeIntervalSince1970: 500), sets: [("Squat", 5)],
                       date: Date(timeIntervalSince1970: 10))
        try addSession(ctx, title: "Later", end: Date(timeIntervalSince1970: 600), sets: [("Squat", 5)],
                       date: Date(timeIntervalSince1970: 5))
        let list = WatchLiftSources.load(from: ctx)
        #expect(list.map(\.title) == ["Later", "Strength"])
    }

    @Test func templateStartCreatesNewSessionAndLeavesSourceUntouched() throws {
        let ctx = try makeContext()
        let source = try addSession(ctx, title: "Push", end: Date(timeIntervalSince1970: 900),
                                    sets: [("Bench Press", 8), ("Bench Press", 6)])
        let template = try #require(WatchLiftSources.load(from: ctx).first)
        let sourceSetIDs = source.orderedSets.map(\.id)

        let model = WatchStrengthFlowModel(context: ctx)
        model.start(title: template.launch.title, plannedExerciseNames: template.launch.exerciseNames,
                    repLadder: template.launch.repLadder, planPayload: template.launch.planPayload,
                    createSession: true)
        let created = try #require(model.session)
        #expect(created.id != source.id)
        #expect(created.plannedExerciseNames == ["Bench Press"])
        #expect(created.plannedPrescriptions.first?.sets.map(\.targetReps) == [8, 6])
        #expect(source.orderedSets.map(\.id) == sourceSetIDs)
        #expect(source.endedAt == Date(timeIntervalSince1970: 900))
        #expect(created.orderedSets.isEmpty)
    }
}
#endif
