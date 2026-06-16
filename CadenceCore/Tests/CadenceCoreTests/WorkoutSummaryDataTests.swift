import XCTest
import SwiftData
@testable import CadenceCore

@MainActor
final class WorkoutSummaryDataTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    // MARK: Strength

    func testStrengthSummaryBasics() throws {
        let ctx = try makeContext()
        let start = Date(timeIntervalSince1970: 1000)
        let session = try WorkoutRepository.createSession(title: "Push Day", date: start, in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 105, reps: 3, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 140, reps: 5, in: ctx)
        session.endedAt = start.addingTimeInterval(3600)

        let s = WorkoutSummaryData.from(session: session)

        XCTAssertEqual(s.kind, .strength)
        XCTAssertEqual(s.title, "Push Day")
        XCTAssertEqual(s.date, start)
        XCTAssertEqual(s.durationSec, 3600, accuracy: 0.001)
        // totalVolumeKg = 100*5 + 105*3 + 140*5 = 500 + 315 + 700 = 1515
        XCTAssertEqual(s.totalVolumeKg ?? 0, 1515, accuracy: 0.001)
        XCTAssertEqual(s.setCount, 3)
        // totalReps = 5 + 3 + 5 = 13 (round4b feedback #8).
        XCTAssertEqual(s.totalReps, 13)

        // Exercise names/order match exercisesInOrder — both exercises listed
        // (round4b feedback #7: a second exercise must never go missing).
        XCTAssertEqual(s.exercises.count, 2)
        XCTAssertEqual(s.exercises.map(\.name), ["Bench Press", "Back Squat"])
        let benchLine = try XCTUnwrap(s.exercises.first)
        XCTAssertEqual(benchLine.setCount, 2)
        XCTAssertEqual(benchLine.reps, [5, 3])
        XCTAssertEqual(benchLine.topSetWeightKg ?? 0, 105, accuracy: 0.001)

        // Cardio fields nil/empty on a strength summary.
        XCTAssertNil(s.distanceM)
        XCTAssertNil(s.paceSecPerKm)
        XCTAssertNil(s.calories)
        XCTAssertNil(s.avgHR)
        XCTAssertNil(s.maxHR)
        XCTAssertTrue(s.hr.isEmpty)
        XCTAssertTrue(s.route.isEmpty)
    }

    func testStrengthSummaryExcludesPartnerSets() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Bench", date: Date(timeIntervalSince1970: 2000), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)

        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)        // owner
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 10,
                                         performedBy: sam, in: ctx)                                            // partner

        let s = WorkoutSummaryData.from(session: session)
        // Only the owner's set counts toward volume and the exercise line.
        XCTAssertEqual(s.totalVolumeKg ?? 0, 500, accuracy: 0.001)
        XCTAssertEqual(s.setCount, 1)
        XCTAssertEqual(s.exercises.count, 1)
        XCTAssertEqual(s.exercises.first?.reps, [5])
        XCTAssertEqual(s.exercises.first?.topSetWeightKg ?? 0, 100, accuracy: 0.001)
    }

    func testStrengthSummaryExcludesWarmupSets() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Squat", date: Date(timeIntervalSince1970: 3000), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 60, reps: 8, isWarmup: true, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 140, reps: 5, in: ctx)

        let s = WorkoutSummaryData.from(session: session)
        // Warmup excluded from volume, setCount, reps, and top set.
        XCTAssertEqual(s.totalVolumeKg ?? 0, 700, accuracy: 0.001)
        XCTAssertEqual(s.setCount, 1)
        XCTAssertEqual(s.exercises.first?.reps, [5])
        XCTAssertEqual(s.exercises.first?.topSetWeightKg ?? 0, 140, accuracy: 0.001)
    }

    // round4b feedback #7 — an exercise whose only logged sets are warmups used to
    // be silently dropped from the summary, so a logged movement could vanish from
    // history. It must still be listed (its working-set line is simply empty).
    func testStrengthSummaryKeepsExerciseWithOnlyWarmupSets() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Full Body", date: Date(timeIntervalSince1970: 4000), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let curl = try WorkoutRepository.findOrCreateExercise(named: "Barbell Curl", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        // Curl: only a warmup set was logged.
        _ = try WorkoutRepository.addSet(to: session, exercise: curl, weightKg: 20, reps: 12, isWarmup: true, in: ctx)

        let s = WorkoutSummaryData.from(session: session)
        XCTAssertEqual(s.exercises.map(\.name), ["Bench Press", "Barbell Curl"],
                       "both performed exercises must appear, even warmup-only ones")
        XCTAssertEqual(s.exercises.last?.setCount, 0)   // working-set count
        XCTAssertEqual(s.totalReps, 5)                  // only the working set's reps
    }

    // feedback batch 3 — partner sets are excluded from the owner roll-up but
    // surfaced as a separate partner summary so partnered history shows them.
    func testStrengthSummaryCarriesPartnerLines() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Bench", date: Date(timeIntervalSince1970: 6000), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 10, performedBy: sam, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 65, reps: 8, performedBy: sam, in: ctx)

        let s = WorkoutSummaryData.from(session: session)
        XCTAssertEqual(s.partners.count, 1)
        let partner = try XCTUnwrap(s.partners.first)
        XCTAssertEqual(partner.name, "Sam")
        XCTAssertEqual(partner.exercises.map(\.name), ["Bench Press"])
        XCTAssertEqual(partner.exercises.first?.reps, [10, 8])
        XCTAssertEqual(partner.exercises.first?.topSetWeightKg ?? 0, 65, accuracy: 0.001)
    }

    // feedback batch 3 — a bodyweight set is flagged so the view shows "BW".
    func testStrengthSummaryFlagsBodyweight() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Calisthenics", date: Date(timeIntervalSince1970: 7000), in: ctx)
        let pullup = try WorkoutRepository.findOrCreateExercise(named: "Pull-Up", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: pullup, weightKg: 0, reps: 10,
                                         usesBodyweight: true, in: ctx)
        let s = WorkoutSummaryData.from(session: session)
        XCTAssertEqual(s.exercises.first?.usesBodyweight, true)
        XCTAssertEqual(s.exercises.first?.topSetWeightKg ?? -1, 0, accuracy: 0.001)
    }

    func testSwimSummaryShowsLaps() throws {
        let ctx = try makeContext()
        let start = Date(timeIntervalSince1970: 5000)
        let c = try WorkoutRepository.saveSwim(start: start, end: start.addingTimeInterval(900),
                                               laps: 18, targetLaps: 20, in: ctx)
        let s = WorkoutSummaryData.from(cardio: c)
        XCTAssertEqual(s.kind, .cardio)
        XCTAssertEqual(s.title, "Swim")
        XCTAssertEqual(s.laps, 18)
        XCTAssertEqual(s.targetLaps, 20)
        XCTAssertNil(s.distanceM)
    }

    // MARK: Cardio

    func testCardioSummaryPopulatesMetrics() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let end = start.addingTimeInterval(600)   // 10 minutes
        let c = CardioWorkout(type: .walk, start: start, end: end,
                              distance: 2000, activeEnergy: 120,
                              avgHeartRate: 110, maxHeartRate: 135)

        let s = WorkoutSummaryData.from(cardio: c)

        XCTAssertEqual(s.kind, .cardio)
        XCTAssertEqual(s.title, "Walk")
        XCTAssertEqual(s.date, start)
        XCTAssertEqual(s.durationSec, 600, accuracy: 0.001)   // end - start
        XCTAssertEqual(s.distanceM ?? 0, 2000, accuracy: 0.001)
        // pace = 600s / 2km = 300 s/km
        XCTAssertEqual(s.paceSecPerKm ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(s.calories ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(s.avgHR ?? 0, 110, accuracy: 0.001)
        XCTAssertEqual(s.maxHR ?? 0, 135, accuracy: 0.001)

        // Strength fields empty/nil on a cardio summary.
        XCTAssertNil(s.totalVolumeKg)
        XCTAssertEqual(s.setCount, 0)
        XCTAssertTrue(s.exercises.isEmpty)
    }

    func testCardioSummaryCarriesHRAndRoute() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        let c = CardioWorkout(type: .run, start: start, end: start.addingTimeInterval(60), distance: 200)
        c.hrSamples = [HRSample(t: 10, bpm: 120, cardio: c), HRSample(t: 0, bpm: 100, cardio: c)]
        c.routeSamples = [RouteSample(t: 5, lat: 1, lon: 2, cardio: c),
                          RouteSample(t: 0, lat: 3, lon: 4, cardio: c)]

        let s = WorkoutSummaryData.from(cardio: c)
        // Ordered by t ascending.
        XCTAssertEqual(s.hr.map(\.t), [0, 10])
        XCTAssertEqual(s.hr.map(\.bpm), [100, 120])
        XCTAssertEqual(s.route.map(\.lat), [3, 1])
        XCTAssertEqual(s.route.map(\.lon), [4, 2])
    }

    func testCardioSummaryNilDistanceHasNilPace() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let c = CardioWorkout(type: .boxing, start: start, end: start.addingTimeInterval(300))
        let s = WorkoutSummaryData.from(cardio: c)
        XCTAssertNil(s.distanceM)
        XCTAssertNil(s.paceSecPerKm)
    }

    // MARK: Icons — the summary header glyph must match the history-list row

    func testCardioSummaryCarriesPerTypeSymbol() throws {
        // Every cardio type carries its own glyph (not a generic running icon), so the
        // summary header matches the history-list row.
        let start = Date(timeIntervalSince1970: 50_000)
        for type in CardioType.allCases {
            let c = CardioWorkout(type: type, start: start, end: start.addingTimeInterval(600))
            let s = WorkoutSummaryData.from(cardio: c)
            XCTAssertEqual(s.symbol, type.symbol, "\(type.rawValue) summary should use its own symbol")
        }
        // Spot-check the cases from the bug report.
        XCTAssertEqual(WorkoutSummaryData.from(cardio: CardioWorkout(type: .boxing, start: start, end: start)).symbol, "figure.boxing")
        XCTAssertEqual(WorkoutSummaryData.from(cardio: CardioWorkout(type: .swim, start: start, end: start)).symbol, "figure.pool.swim")
        XCTAssertEqual(WorkoutSummaryData.from(cardio: CardioWorkout(type: .walk, start: start, end: start)).symbol, "figure.walk")
    }

    func testStrengthSummaryCarriesSessionSymbol() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Push Day", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        let s = WorkoutSummaryData.from(session: session)
        XCTAssertEqual(s.symbol, session.symbol, "strength summary mirrors the session's history glyph")
        XCTAssertEqual(s.symbol, "dumbbell")
    }

    // MARK: Feedback batch 6 — Other Cardio title, logged flag, warm/cool

    func testOtherCardioUsesCustomTitle() throws {
        let start = Date(timeIntervalSince1970: 40_000)
        let c = CardioWorkout(type: .other, start: start, end: start.addingTimeInterval(1800),
                              customTitle: "Rowing")
        let s = WorkoutSummaryData.from(cardio: c)
        XCTAssertEqual(s.title, "Rowing", "free-text Other Cardio label wins over the type name")
    }

    func testOtherCardioBlankCustomTitleFallsBackToTypeName() throws {
        let start = Date(timeIntervalSince1970: 41_000)
        let c = CardioWorkout(type: .other, start: start, end: start.addingTimeInterval(60),
                              customTitle: "   ")
        XCTAssertEqual(c.displayTitle, "Other", "whitespace-only label is ignored")
        XCTAssertEqual(WorkoutSummaryData.from(cardio: c).title, "Other")
    }

    func testLoggedFlagFlowsThrough() throws {
        let start = Date(timeIntervalSince1970: 42_000)
        let logged = CardioWorkout(type: .run, start: start, end: start.addingTimeInterval(600), isLogged: true)
        XCTAssertTrue(WorkoutSummaryData.from(cardio: logged).isLogged)

        let live = CardioWorkout(type: .run, start: start, end: start.addingTimeInterval(600))
        XCTAssertFalse(WorkoutSummaryData.from(cardio: live).isLogged)
    }

    func testStrengthSummaryCarriesLoggedAndWarmCool() throws {
        let ctx = try makeContext()
        let start = Date(timeIntervalSince1970: 43_000)
        let session = try WorkoutRepository.createSession(title: "Logged Push", date: start, in: ctx)
        session.isLogged = true
        session.warmupSeconds = 180
        session.cooldownSeconds = 90
        let s = WorkoutSummaryData.from(session: session)
        XCTAssertTrue(s.isLogged)
        XCTAssertEqual(s.warmupSec, 180, accuracy: 0.001)
        XCTAssertEqual(s.cooldownSec, 90, accuracy: 0.001)
    }

    // The pure history glyph (feedback batch 6): CrossFit / bodyweight / weighted.
    func testSessionSymbolReflectsKind() throws {
        let ctx = try makeContext()
        let crossfit = try WorkoutRepository.createSession(title: "CrossFit – Fran", date: Date(), in: ctx)
        XCTAssertEqual(crossfit.symbol, "figure.strengthtraining.functional")

        let calisthenics = try WorkoutRepository.createSession(title: "Calisthenics", date: Date(), in: ctx)
        let pullup = try WorkoutRepository.findOrCreateExercise(named: "Pull-Up", in: ctx)
        _ = try WorkoutRepository.addSet(to: calisthenics, exercise: pullup, weightKg: 0, reps: 10,
                                         usesBodyweight: true, in: ctx)
        XCTAssertEqual(calisthenics.symbol, "figure.strengthtraining.traditional")

        let weights = try WorkoutRepository.createSession(title: "Push Day", date: Date(), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: weights, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        XCTAssertEqual(weights.symbol, "dumbbell")
    }
}
