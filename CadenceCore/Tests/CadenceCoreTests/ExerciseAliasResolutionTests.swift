#if canImport(SwiftData)
import Testing
import SwiftData
@testable import CadenceCore

struct ExerciseAliasResolutionTests {

    private func makeContext(seed: Bool = false) throws -> ModelContext {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        if seed {
            _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
        }
        return context
    }

    @Test func commonAliasesResolveToBuiltInTemplates() {
        let lateral = ExerciseLibrary.template(matching: "Lateral Raise")
        #expect(lateral?.name == "Dumbbell Lateral Raise")
        #expect(lateral?.primaryMuscles == ["shoulders"])

        let pushdown = ExerciseLibrary.template(matching: "Tricep Pushdown")
        #expect(pushdown?.name == "Triceps Pushdown")
        #expect(pushdown?.primaryMuscles == ["triceps"])
    }

    @Test func findOrCreateUsesBuiltInsForWatchAliasNames() throws {
        let context = try makeContext()

        let lateral = try WorkoutRepository.findOrCreateExercise(named: "Lateral Raise", in: context)
        #expect(lateral.name == "Dumbbell Lateral Raise")
        #expect(!lateral.isCustom)
        #expect(lateral.primaryMuscles == ["shoulders"])

        let pushdown = try WorkoutRepository.findOrCreateExercise(named: "Tricep Pushdown", in: context)
        #expect(pushdown.name == "Triceps Pushdown")
        #expect(!pushdown.isCustom)
        #expect(pushdown.primaryMuscles == ["triceps"])

        let customs = try WorkoutRepository.allExercises(context).filter(\.isCustom)
        #expect(customs.isEmpty)
    }

    @Test func seedRepairsEmptyCustomAliasesPreservingWatchSets() throws {
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
        #expect(before.incompleteCustomExerciseNames == ["Tricep Pushdown"])

        #expect(try WorkoutRepository.seedStarterLibraryIfNeeded(context))

        let exercises = try WorkoutRepository.allExercises(context)
        #expect(!exercises.contains { $0.isCustom && $0.name == "Tricep Pushdown" })
        let builtIn = try #require(exercises.first { !$0.isCustom && $0.name == "Triceps Pushdown" })
        #expect(builtIn.primaryMuscles == ["triceps"])
        #expect(builtIn.sets?.count == 1)
        #expect(builtIn.isFavorite)

        let savedSession = try #require(try WorkoutRepository.allSessions(context).first)
        #expect(savedSession.plannedExerciseNames == ["Triceps Pushdown"])
        #expect(savedSession.orderedSets.first?.exercise?.name == "Triceps Pushdown")
        let after = TrainingFacts.make(sessions: [savedSession], now: session.date,
                                       goal: .hypertrophy, experience: .intermediate)
        #expect(after.incompleteCustomExerciseNames.isEmpty)
    }

    @Test func importMapsEmptyCustomAliasExportToBuiltIn() throws {
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

        #expect(try WorkoutRepository.merge(export, in: context) == 1)

        let exercises = try WorkoutRepository.allExercises(context)
        #expect(!exercises.contains { $0.isCustom && $0.name == "Lateral Raise" })
        let builtIn = try #require(exercises.first { !$0.isCustom && $0.name == "Dumbbell Lateral Raise" })
        #expect(builtIn.primaryMuscles == ["shoulders"])
        #expect(builtIn.sets?.count == 1)

        let session = try #require(try WorkoutRepository.allSessions(context).first)
        #expect(session.plannedExerciseNames == ["Dumbbell Lateral Raise"])
        #expect(session.orderedSets.first?.exercise?.name == "Dumbbell Lateral Raise")
    }
}
#endif
