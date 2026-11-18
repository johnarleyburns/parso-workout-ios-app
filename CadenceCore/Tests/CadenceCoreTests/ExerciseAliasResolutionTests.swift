import XCTest
import SwiftData
@testable import CadenceCore

final class ExerciseAliasResolutionTests: XCTestCase {

    private func makeContext(seed: Bool = false) throws -> ModelContext {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        if seed {
            _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
        }
        return context
    }

    func testCommonAliasesResolveToBuiltInTemplates() {
        let lateral = ExerciseLibrary.template(matching: "Lateral Raise")
        XCTAssertEqual(lateral?.name, "Dumbbell Lateral Raise")
        XCTAssertEqual(lateral?.primaryMuscles, ["shoulders"])

        let pushdown = ExerciseLibrary.template(matching: "Tricep Pushdown")
        XCTAssertEqual(pushdown?.name, "Triceps Pushdown")
        XCTAssertEqual(pushdown?.primaryMuscles, ["triceps"])
    }

    func testFindOrCreateUsesBuiltInsForWatchAliasNames() throws {
        let context = try makeContext()

        let lateral = try WorkoutRepository.findOrCreateExercise(named: "Lateral Raise", in: context)
        XCTAssertEqual(lateral.name, "Dumbbell Lateral Raise")
        XCTAssertFalse(lateral.isCustom)
        XCTAssertEqual(lateral.primaryMuscles, ["shoulders"])

        let pushdown = try WorkoutRepository.findOrCreateExercise(named: "Tricep Pushdown", in: context)
        XCTAssertEqual(pushdown.name, "Triceps Pushdown")
        XCTAssertFalse(pushdown.isCustom)
        XCTAssertEqual(pushdown.primaryMuscles, ["triceps"])

        let customs = try WorkoutRepository.allExercises(context).filter(\.isCustom)
        XCTAssertTrue(customs.isEmpty)
    }

    func testSeedRepairsEmptyCustomAliasesPreservingWatchSets() throws {
        let context = try makeContext()
        let custom = Exercise(name: "Tricep Pushdown", isCustom: true)
        custom.isFavorite = true
        let session = WorkoutSession(title: "Watch Strength", date: Date(timeIntervalSince1970: 1_800_000_000))
        session.plannedExerciseNames = ["Tricep Pushdown"]
        context.insert(custom)
        context.insert(session)
        context.insert(SetEntry(weight: 25, reps: 12, order: 0, completedAt: session.date,
                                session: session, exercise: custom))
        try context.save()

        let before = TrainingFacts.make(sessions: [session], now: session.date,
                                        goal: .hypertrophy, experience: .intermediate)
        XCTAssertEqual(before.incompleteCustomExerciseNames, ["Tricep Pushdown"])

        XCTAssertTrue(try WorkoutRepository.seedStarterLibraryIfNeeded(context))

        let exercises = try WorkoutRepository.allExercises(context)
        XCTAssertFalse(exercises.contains { $0.isCustom && $0.name == "Tricep Pushdown" })
        let builtIn = try XCTUnwrap(exercises.first { !$0.isCustom && $0.name == "Triceps Pushdown" })
        XCTAssertEqual(builtIn.primaryMuscles, ["triceps"])
        XCTAssertEqual(builtIn.sets?.count, 1)
        XCTAssertTrue(builtIn.isFavorite)

        let savedSession = try XCTUnwrap(try WorkoutRepository.allSessions(context).first)
        XCTAssertEqual(savedSession.plannedExerciseNames, ["Triceps Pushdown"])
        XCTAssertEqual(savedSession.orderedSets.first?.exercise?.name, "Triceps Pushdown")
        let after = TrainingFacts.make(sessions: [savedSession], now: session.date,
                                       goal: .hypertrophy, experience: .intermediate)
        XCTAssertTrue(after.incompleteCustomExerciseNames.isEmpty)
    }

    func testImportMapsEmptyCustomAliasExportToBuiltIn() throws {
        let context = try makeContext(seed: true)
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let export = CadenceExport(
            sessions: [
                ExportSession(
                    id: UUID(),
                    title: "Watch Strength",
                    date: now,
                    notes: nil,
                    sets: [
                        ExportSet(id: UUID(), exerciseName: "Lateral Raise", category: nil,
                                  weightKg: 10, reps: 12, order: 0, isWarmup: false,
                                  rpe: nil, note: nil, completedAt: now),
                    ],
                    plannedExerciseNames: ["Lateral Raise"]
                ),
            ],
            exercises: [
                ExportExercise(id: UUID(), name: "Lateral Raise"),
            ]
        )

        XCTAssertEqual(try WorkoutRepository.merge(export, in: context), 1)

        let exercises = try WorkoutRepository.allExercises(context)
        XCTAssertFalse(exercises.contains { $0.isCustom && $0.name == "Lateral Raise" })
        let builtIn = try XCTUnwrap(exercises.first { !$0.isCustom && $0.name == "Dumbbell Lateral Raise" })
        XCTAssertEqual(builtIn.primaryMuscles, ["shoulders"])
        XCTAssertEqual(builtIn.sets?.count, 1)

        let session = try XCTUnwrap(try WorkoutRepository.allSessions(context).first)
        XCTAssertEqual(session.plannedExerciseNames, ["Dumbbell Lateral Raise"])
        XCTAssertEqual(session.orderedSets.first?.exercise?.name, "Dumbbell Lateral Raise")
    }
}
