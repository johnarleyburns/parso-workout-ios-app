import XCTest
import SwiftData
@testable import CadenceCore

/// strength-pivot P5.1 — the prescriptive inference engine over `TrainingFacts`.
final class RecommendationEngineTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    /// Build a synthetic facts snapshot directly (bypassing the store) for
    /// table-driven rule tests, mirroring how `TrainingFacts.make` would fill it.
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

    // MARK: cold-start

    func testColdStartReturnsStarter() {
        let recs = RecommendationEngine.run(facts())
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs.first?.kind, .starter)
        XCTAssertNotNil(recs.first?.target)
        XCTAssertEqual(RecommendationEngine.top(facts()).kind, .starter)
    }

    func testStarterUsesGoalRepRangeAndRIR() {
        let starter = KnowledgeBase.starter(goal: .hypertrophy, experience: .intermediate)
        XCTAssertEqual(starter.target?.repsLow, 6)
        XCTAssertEqual(starter.target?.repsHigh, 12)
        XCTAssertEqual(starter.target?.rir, 1)
        XCTAssertEqual(starter.target?.sets, 3)
    }

    // MARK: progression (double progression)

    func testAddsRepWhenBelowTopOfRange() {
        // strength range 3–5; 4 reps → aim for 5 at the same load.
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 4, trend: .flat)], goal: .strength)
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.Squat" }
        XCTAssertEqual(rec?.target?.repsLow, 5)
        XCTAssertEqual(rec?.target?.repsHigh, 5)
        XCTAssertEqual(rec?.target?.loadKg, 100)        // same load
        XCTAssertEqual(rec?.target?.rir, 2)
        XCTAssertEqual(rec?.confidence, .high)          // flat = clear plateau cue
    }

    func testAddsLoadAtTopOfRange() {
        // strength range 3–5; already at 5 reps → add 2.5 kg, reset to 3 reps.
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 5, trend: .rising)], goal: .strength)
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.Squat" }
        XCTAssertEqual(rec?.target?.loadKg, 102.5)
        XCTAssertEqual(rec?.target?.repsLow, 3)         // reset to bottom
        XCTAssertEqual(rec?.confidence, .moderate)      // rising = keep going
    }

    // MARK: deload

    func testDecliningLiftGetsDeloadNotProgression() {
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 5, trend: .declining)], goal: .strength)
        let recs = RecommendationEngine.run(f)
        XCTAssertNil(recs.first { $0.id == "progression.Squat" })
        let deload = recs.first { $0.id == "deload.Squat" }
        XCTAssertEqual(deload?.kind, .deload)
        XCTAssertEqual(deload?.target?.loadKg, 90)      // ~10% off, rounded to 2.5
        XCTAssertEqual(deload?.target?.rir, 3)          // more in reserve
        XCTAssertEqual(deload?.citation.id, CitationRegistry.rpeAutoregulation.id)
    }

    func testDeloadRanksBeforeProgression() {
        let f = facts(snapshots: [
            snapshot("Bench", weight: 80, reps: 4, trend: .flat),       // → progression
            snapshot("Squat", weight: 100, reps: 5, trend: .declining), // → deload
        ], goal: .strength)
        XCTAssertEqual(RecommendationEngine.run(f).first?.id, "deload.Squat")
    }

    // MARK: add volume

    func testAddVolumeBelowMEV() {
        // 2 sets/week is below the minimum effective volume for any part.
        let f = facts(weeklySets: [.chest: 2], goal: .hypertrophy)
        let rec = RecommendationEngine.run(f).first { $0.id == "addVolume.chest" }
        XCTAssertEqual(rec?.kind, .addVolume)
        XCTAssertEqual(rec?.part, .chest)
        XCTAssertNil(rec?.target?.loadKg)               // volume, not a specific load
        XCTAssertGreaterThanOrEqual(rec?.target?.sets ?? 0, 1)
        XCTAssertEqual(rec?.citation.id, CitationRegistry.volumeDoseResponse.id)
    }

    func testProductiveVolumeProducesNoAddVolume() {
        // A large weekly volume is well above MEV → no add-volume recommendation.
        let f = facts(weeklySets: [.chest: 40], goal: .hypertrophy)
        XCTAssertNil(RecommendationEngine.run(f).first { $0.id == "addVolume.chest" })
    }

    // MARK: invariants

    func testEveryRecommendationIsCited() {
        let known = Set(CitationRegistry.all.map(\.id))
        let f = facts(snapshots: [
            snapshot("Bench", weight: 80, reps: 4, trend: .flat),
            snapshot("Squat", weight: 100, reps: 5, trend: .declining),
        ], weeklySets: [.chest: 2], goal: .strength)
        let recs = RecommendationEngine.run(f)
        XCTAssertFalse(recs.isEmpty)
        for rec in recs {
            XCTAssertTrue(known.contains(rec.citation.id), "\(rec.id) cites unknown \(rec.citation.id)")
        }
    }

    func testIdempotentForIdenticalFacts() {
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 4, trend: .flat)],
                      weeklySets: [.chest: 2], goal: .strength)
        XCTAssertEqual(RecommendationEngine.run(f).map(\.id), RecommendationEngine.run(f).map(\.id))
    }

    func testRoundLoadSnapsToIncrement() {
        XCTAssertEqual(PrescriptionMath.roundLoad(101.2), 100)
        XCTAssertEqual(PrescriptionMath.roundLoad(101.3), 102.5)
        XCTAssertEqual(PrescriptionMath.roundLoad(100), 100)
    }

    // MARK: integration through TrainingFacts.make

    func testMakeWiresLiftSnapshotIntoProgression() throws {
        let ctx = try makeContext()
        let now = Date()
        let s = try WorkoutRepository.createSession(date: now.addingTimeInterval(-86_400), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "BackSquat", primaryMuscles: ["quadriceps"], secondaryMuscles: ["glutes"], in: ctx)
        // 5 reps at 60 kg, strength goal (range 3–5) → at the top → add load to 62.5.
        _ = try WorkoutRepository.addSet(to: s, exercise: squat, weightKg: 60, reps: 5, rpe: 8, in: ctx)
        let f = TrainingFacts.make(sessions: [s], now: now, goal: .strength, experience: .intermediate)
        XCTAssertNotNil(f.liftSnapshots["BackSquat"])
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.BackSquat" }
        XCTAssertEqual(rec?.target?.loadKg, 62.5)
    }
}
