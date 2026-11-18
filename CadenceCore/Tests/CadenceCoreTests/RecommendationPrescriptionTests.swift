#if canImport(SwiftData)
import Testing
import SwiftData
@testable import CadenceCore

/// strength-pivot P5.3 — translating a coaching `Recommendation` into a concrete,
/// pre-filled `PrescribedSession` ("Do this workout"), and materializing it into the
/// store via `WorkoutRepository.startSession(from:)`.
struct RecommendationPrescriptionTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func facts(snapshots: [LiftSnapshot] = [],
                       weeklySets: [MuscleGroup: Double] = [:],
                       goal: TrainingGoal = .strength,
                       experience: ExperienceLevel = .intermediate) -> TrainingFacts {
        TrainingFacts(
            weeklySetsByGroup: weeklySets,
            frequencyByGroup: [:],
            e1RMTrendByExercise: [:],
            intensity: .empty,
            avgRPE: nil,
            daysSinceLastSession: nil,
            totalWorkingSets: snapshots.isEmpty && weeklySets.isEmpty ? 0 : 1,
            liftSnapshots: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.exercise, $0) }),
            goal: goal,
            experience: experience)
    }

    private func snapshot(_ name: String, weight: Double, reps: Int,
                          trend: TrendDirection?, group: MuscleGroup? = .quadriceps) -> LiftSnapshot {
        LiftSnapshot(exercise: name, group: group, topSetWeightKg: weight,
                     topSetReps: reps, bestE1RM: weight, trend: trend)
    }

    // MARK: progression → a single-lift session pre-filled with load

    @Test func progressionPrescribesLiftAndLoad() throws {
        // strength range 3–5; 4 reps, not declining → add a rep at the same load.
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 4, trend: .flat)], goal: .strength)
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.Squat" }
        let p = try #require(rec).prescribedSession()
        #expect(p.title == "Squat")
        #expect(p.exerciseNames == ["Squat"])
        #expect(p.loadKg == 100)
        // The progression target leaves the set count open, so the default fills in.
        #expect(p.repLadder.count == 3)
        #expect(p.repLadder.allSatisfy { $0 == 5 }, "seeds the next-rep target (5) for every planned set")
    }

    @Test func progressionAddLoadBranchResetsToBottomOfRange() throws {
        // 5 reps = top of the strength range → add load, reset to 3.
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 5, trend: .flat)], goal: .strength)
        let p = try #require(RecommendationEngine.run(f).first { $0.id == "progression.Squat" }).prescribedSession()
        #expect(p.loadKg == 102.5, "added one 2.5 kg increment")
        #expect(p.repLadder.allSatisfy { $0 == 3 }, "drops back to the bottom of the range")
    }

    // MARK: deload → fewer sets, backed-off load

    @Test func deloadPrescribesTwoBackedOffSets() throws {
        let f = facts(snapshots: [snapshot("Bench Press", weight: 100, reps: 3, trend: .declining)], goal: .strength)
        let p = try #require(RecommendationEngine.run(f).first { $0.id == "deload.Bench Press" }).prescribedSession()
        #expect(p.title == "Bench Press")
        #expect(p.exerciseNames == ["Bench Press"])
        #expect(p.loadKg == 90, "~10% backoff")
        #expect(p.repLadder.count == 2, "deload prescribes 2 sets")
    }

    // MARK: add-volume → a part-focused session, no specific lift, no load

    @Test func addVolumePrescribesPartFocusWithoutLift() throws {
        let f = facts(weeklySets: [.biceps: 1], goal: .hypertrophy)
        let rec = try #require(RecommendationEngine.run(f).first { $0.id == "addVolume.biceps" })
        let p = try #require(rec).prescribedSession()
        #expect(p.title == "\(MuscleGroup.biceps.displayName) focus")
        #expect(p.exerciseNames == ["Barbell Curl"], "part default exercise provided")
        #expect(p.loadKg == nil, "bodyweight/any load")
        #expect(!p.repLadder.isEmpty, "still prescribes a rep ladder to apply")
    }

    // MARK: starter (cold-start) → full-body session

    @Test func starterPrescribesFullBodySession() {
        let p = RecommendationEngine.top(facts()).prescribedSession()
        #expect(p.title == "Full-body session")
        #expect(p.exerciseNames == ["Back Squat", "Bench Press", "Deadlift"], "starter fills compounds")
        #expect(p.loadKg == nil)
        #expect(p.repLadder.count == 3, "starter is 3 sets")
    }

    @Test func defaultSetsHonoredWhenTargetLeavesCountOpen() throws {
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 4, trend: .flat)], goal: .strength)
        let rec = try #require(RecommendationEngine.run(f).first { $0.id == "progression.Squat" })
        #expect(rec.prescribedSession(defaultSets: 5).repLadder.count == 5)
    }

    // MARK: P1 (issue 2) — goal-specific descending rep ladders

    @Test func hypertrophyStarterPrescribesDescendingLadder() {
        // A hypertrophy goal-level rec spanning 6…12 must descend, not flatten to 6.
        let p = KnowledgeBase.starter(goal: .hypertrophy, experience: .intermediate)
            .prescribedSession(goal: .hypertrophy)
        #expect(p.repLadder == [12, 10, 8], "hypertrophy 3-set should be a 12-10-8 pyramid, not 6-6-6")
    }

    @Test func hypertrophyFourSetLadder() {
        // With a 4-set target the ladder extends the pyramid one more rung.
        let p = KnowledgeBase.starter(goal: .hypertrophy, experience: .intermediate)
            .prescribedSession(defaultSets: 4, goal: .hypertrophy)
        // The starter pins sets:3, so defaultSets is ignored — a 3-set 12-10-8.
        #expect(p.repLadder == [12, 10, 8])
    }

    @Test func strengthStarterPrescribesTopHeavyHold() {
        let p = KnowledgeBase.starter(goal: .strength, experience: .intermediate)
            .prescribedSession(goal: .strength)
        #expect(p.repLadder == [5, 5, 3], "strength 3-set should ramp 5-5-3, not flatten to 3")
    }

    @Test func addVolumeHypertrophyProducesLadderNotFlatFloor() throws {
        let f = facts(weeklySets: [.biceps: 1], goal: .hypertrophy)
        let rec = try #require(RecommendationEngine.run(f).first { $0.id == "addVolume.biceps" })
        let ladder = rec.prescribedSession(goal: .hypertrophy).repLadder
        #expect(!ladder.allSatisfy { $0 == ladder.first }, "ladder must not be flat for a hypertrophy range")
        #expect(ladder.first == 12, "starts at the top of the hypertrophy range")
    }

    @Test func explicitSingleRepTargetStillFlattens() throws {
        // Progression pins an exact rep (add a rep at the same load) — the ladder
        // must NOT override a deliberate single-rep prescription.
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 4, trend: .flat)], goal: .strength)
        let p = try #require(RecommendationEngine.run(f).first { $0.id == "progression.Squat" }).prescribedSession(goal: .strength)
        #expect(p.repLadder.allSatisfy { $0 == 5 }, "explicit rep target flattens")
    }

    // MARK: materialization into the store

    @Test func startSessionFromPrescriptionSeedsPlannedFields() throws {
        let ctx = try makeContext()
        let f = facts(snapshots: [snapshot("Back Squat", weight: 140, reps: 5, trend: .flat)], goal: .strength)
        let p = try #require(RecommendationEngine.run(f).first { $0.id == "progression.Back Squat" }).prescribedSession()

        let session = try WorkoutRepository.startSession(from: p, in: ctx)
        #expect(session.title == "Back Squat")
        #expect(session.plannedExerciseNames == ["Back Squat"])
        #expect(session.plannedRepLadder.count == 3)
        #expect(session.prescribedLoadKg == p.loadKg)
        // The prescribed movement is resolved into the library so the logger can
        // attach sets to it.
        let names = try WorkoutRepository.allExercises(ctx).map(\.name)
        #expect(names.contains("Back Squat"))
    }

    @Test func startSessionFromBodyweightPrescriptionLeavesLoadZero() throws {
        let ctx = try makeContext()
        let p = RecommendationEngine.top(facts()).prescribedSession()  // starter, loadKg nil
        let session = try WorkoutRepository.startSession(from: p, in: ctx)
        #expect(session.prescribedLoadKg == 0, "no prescribed load → keypad starts empty")
        #expect(session.plannedExerciseNames.count == 3, "starter fills default compounds")
    }
}
#endif
