import XCTest
import SwiftData
@testable import CadenceCore

/// strength-pivot P5.3 — translating a coaching `Recommendation` into a concrete,
/// pre-filled `PrescribedSession` ("Do this workout"), and materializing it into the
/// store via `WorkoutRepository.startSession(from:)`.
final class RecommendationPrescriptionTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func facts(snapshots: [LiftSnapshot] = [],
                       weeklySets: [BodyPart: Double] = [:],
                       goal: TrainingGoal = .strength,
                       experience: ExperienceLevel = .intermediate) -> TrainingFacts {
        TrainingFacts(
            weeklySetsByPart: weeklySets,
            frequencyByPart: [:],
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
                          trend: TrendDirection?, part: BodyPart? = .legs) -> LiftSnapshot {
        LiftSnapshot(exercise: name, part: part, topSetWeightKg: weight,
                     topSetReps: reps, bestE1RM: weight, trend: trend)
    }

    // MARK: progression → a single-lift session pre-filled with load

    func testProgressionPrescribesLiftAndLoad() throws {
        // strength range 3–5; 4 reps, not declining → add a rep at the same load.
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 4, trend: .flat)], goal: .strength)
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.Squat" }
        let p = try XCTUnwrap(rec).prescribedSession()
        XCTAssertEqual(p.title, "Squat")
        XCTAssertEqual(p.exerciseNames, ["Squat"])
        XCTAssertEqual(p.loadKg, 100)
        // The progression target leaves the set count open, so the default fills in.
        XCTAssertEqual(p.repLadder.count, 3)
        XCTAssertTrue(p.repLadder.allSatisfy { $0 == 5 }, "seeds the next-rep target (5) for every planned set")
    }

    func testProgressionAddLoadBranchResetsToBottomOfRange() throws {
        // 5 reps = top of the strength range → add load, reset to 3.
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 5, trend: .flat)], goal: .strength)
        let p = try XCTUnwrap(RecommendationEngine.run(f).first { $0.id == "progression.Squat" }).prescribedSession()
        XCTAssertEqual(p.loadKg, 102.5, "added one 2.5 kg increment")
        XCTAssertTrue(p.repLadder.allSatisfy { $0 == 3 }, "drops back to the bottom of the range")
    }

    // MARK: deload → fewer sets, backed-off load

    func testDeloadPrescribesTwoBackedOffSets() throws {
        let f = facts(snapshots: [snapshot("Bench Press", weight: 100, reps: 3, trend: .declining)], goal: .strength)
        let p = try XCTUnwrap(RecommendationEngine.run(f).first { $0.id == "deload.Bench Press" }).prescribedSession()
        XCTAssertEqual(p.title, "Bench Press")
        XCTAssertEqual(p.exerciseNames, ["Bench Press"])
        XCTAssertEqual(p.loadKg, 90, "~10% backoff")
        XCTAssertEqual(p.repLadder.count, 2, "deload prescribes 2 sets")
    }

    // MARK: add-volume → a part-focused session, no specific lift, no load

    func testAddVolumePrescribesPartFocusWithoutLift() throws {
        let f = facts(weeklySets: [.biceps: 1], goal: .hypertrophy)
        let rec = try XCTUnwrap(RecommendationEngine.run(f).first { $0.id == "addVolume.biceps" })
        let p = try XCTUnwrap(rec).prescribedSession()
        XCTAssertEqual(p.title, "\(BodyPart.biceps.displayName) focus")
        XCTAssertEqual(p.exerciseNames, ["Barbell Curl"], "part default exercise provided")
        XCTAssertNil(p.loadKg, "bodyweight/any load")
        XCTAssertFalse(p.repLadder.isEmpty, "still prescribes a rep ladder to apply")
    }

    // MARK: starter (cold-start) → full-body session

    func testStarterPrescribesFullBodySession() {
        let p = RecommendationEngine.top(facts()).prescribedSession()
        XCTAssertEqual(p.title, "Full-body session")
        XCTAssertEqual(p.exerciseNames, ["Back Squat", "Bench Press", "Deadlift"], "starter fills compounds")
        XCTAssertNil(p.loadKg)
        XCTAssertEqual(p.repLadder.count, 3, "starter is 3 sets")
    }

    func testDefaultSetsHonoredWhenTargetLeavesCountOpen() throws {
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 4, trend: .flat)], goal: .strength)
        let rec = try XCTUnwrap(RecommendationEngine.run(f).first { $0.id == "progression.Squat" })
        XCTAssertEqual(rec.prescribedSession(defaultSets: 5).repLadder.count, 5)
    }

    // MARK: materialization into the store

    func testStartSessionFromPrescriptionSeedsPlannedFields() throws {
        let ctx = try makeContext()
        let f = facts(snapshots: [snapshot("Back Squat", weight: 140, reps: 5, trend: .flat)], goal: .strength)
        let p = try XCTUnwrap(RecommendationEngine.run(f).first { $0.id == "progression.Back Squat" }).prescribedSession()

        let session = try WorkoutRepository.startSession(from: p, in: ctx)
        XCTAssertEqual(session.title, "Back Squat")
        XCTAssertEqual(session.plannedExerciseNames, ["Back Squat"])
        XCTAssertEqual(session.plannedRepLadder.count, 3)
        XCTAssertEqual(session.prescribedLoadKg, p.loadKg)
        // The prescribed movement is resolved into the library so the logger can
        // attach sets to it.
        let names = try WorkoutRepository.allExercises(ctx).map(\.name)
        XCTAssertTrue(names.contains("Back Squat"))
    }

    func testStartSessionFromBodyweightPrescriptionLeavesLoadZero() throws {
        let ctx = try makeContext()
        let p = RecommendationEngine.top(facts()).prescribedSession()  // starter, loadKg nil
        let session = try WorkoutRepository.startSession(from: p, in: ctx)
        XCTAssertEqual(session.prescribedLoadKg, 0, "no prescribed load → keypad starts empty")
        XCTAssertEqual(session.plannedExerciseNames.count, 3, "starter fills default compounds")
    }
}
