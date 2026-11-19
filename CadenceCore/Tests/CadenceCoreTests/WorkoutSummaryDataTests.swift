#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

@MainActor
struct WorkoutSummaryDataTests {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    // MARK: Strength

    @Test func strengthSummaryBasics() throws {
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

        #expect(s.kind == .strength)
        #expect(s.title == "Push Day")
        #expect(s.date == start)
        #expect(abs(s.durationSec - 3600) <= 0.001)
        // totalVolumeKg = 100*5 + 105*3 + 140*5 = 500 + 315 + 700 = 1515
        #expect(abs((s.totalVolumeKg ?? 0) - 1515) <= 0.001)
        #expect(s.setCount == 3)
        // totalReps = 5 + 3 + 5 = 13 (round4b feedback #8).
        #expect(s.totalReps == 13)

        // Exercise names/order match exercisesInOrder — both exercises listed
        // (round4b feedback #7: a second exercise must never go missing).
        #expect(s.exercises.count == 2)
        #expect(s.exercises.map(\.name) == ["Bench Press", "Back Squat"])
        let benchLine = try #require(s.exercises.first)
        #expect(benchLine.setCount == 2)
        #expect(benchLine.reps == [5, 3])
        #expect(abs((benchLine.topSetWeightKg ?? 0) - 105) <= 0.001)

        // Cardio fields nil/empty on a strength summary.
        #expect(s.distanceM == nil)
        #expect(s.paceSecPerKm == nil)
        #expect(s.calories == nil)
        #expect(s.avgHR == nil)
        #expect(s.maxHR == nil)
        #expect(s.hr.isEmpty)
        #expect(s.route.isEmpty)
    }

    @Test func strengthSummaryExcludesPartnerSets() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Bench", date: Date(timeIntervalSince1970: 2000), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)

        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)        // owner
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 10,
                                         performedBy: sam, in: ctx)                                            // partner

        let s = WorkoutSummaryData.from(session: session)
        // Only the owner's set counts toward volume and the exercise line.
        #expect(abs((s.totalVolumeKg ?? 0) - 500) <= 0.001)
        #expect(s.setCount == 1)
        #expect(s.exercises.count == 1)
        #expect(s.exercises.first?.reps == [5])
        #expect(abs((s.exercises.first?.topSetWeightKg ?? 0) - 100) <= 0.001)
    }

    @Test func strengthSummaryExcludesWarmupSets() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Squat", date: Date(timeIntervalSince1970: 3000), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 60, reps: 8, isWarmup: true, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 140, reps: 5, in: ctx)

        let s = WorkoutSummaryData.from(session: session)
        // Warmup excluded from volume, setCount, reps, and top set.
        #expect(abs((s.totalVolumeKg ?? 0) - 700) <= 0.001)
        #expect(s.setCount == 1)
        #expect(s.exercises.first?.reps == [5])
        #expect(abs((s.exercises.first?.topSetWeightKg ?? 0) - 140) <= 0.001)
    }

    // round4b feedback #7 — an exercise whose only logged sets are warmups used to
    // be silently dropped from the summary, so a logged movement could vanish from
    // history. It must still be listed (its working-set line is simply empty).
    @Test func strengthSummaryKeepsExerciseWithOnlyWarmupSets() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Full Body", date: Date(timeIntervalSince1970: 4000), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let curl = try WorkoutRepository.findOrCreateExercise(named: "Barbell Curl", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        // Curl: only a warmup set was logged.
        _ = try WorkoutRepository.addSet(to: session, exercise: curl, weightKg: 20, reps: 12, isWarmup: true, in: ctx)

        let s = WorkoutSummaryData.from(session: session)
        #expect(s.exercises.map(\.name) == ["Bench Press", "Barbell Curl"],
                       "both performed exercises must appear, even warmup-only ones")
        #expect(s.exercises.last?.setCount == 0)   // working-set count
        #expect(s.totalReps == 5)                  // only the working set's reps
    }

    // feedback batch 3 — partner sets are excluded from the owner roll-up but
    // surfaced as a separate partner summary so partnered history shows them.
    @Test func strengthSummaryCarriesPartnerLines() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Bench", date: Date(timeIntervalSince1970: 6000), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 10, performedBy: sam, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 65, reps: 8, performedBy: sam, in: ctx)

        let s = WorkoutSummaryData.from(session: session)
        #expect(s.partners.count == 1)
        let partner = try #require(s.partners.first)
        #expect(partner.name == "Sam")
        #expect(partner.exercises.map(\.name) == ["Bench Press"])
        #expect(partner.exercises.first?.reps == [10, 8])
        #expect(abs((partner.exercises.first?.topSetWeightKg ?? 0) - 65) <= 0.001)
        #expect(Set(s.volumeByPerformer.keys) == Set(["Me", "Sam"]))
        #expect(!s.volumeByPerformer["Me", default: [:]].isEmpty)
        #expect(!s.volumeByPerformer["Sam", default: [:]].isEmpty)
    }

    // feedback batch 3 — a bodyweight set is flagged so the view shows "BW".
    @Test func strengthSummaryFlagsBodyweight() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Calisthenics", date: Date(timeIntervalSince1970: 7000), in: ctx)
        let pullup = try WorkoutRepository.findOrCreateExercise(named: "Pull-Up", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: pullup, weightKg: 0, reps: 10,
                                         usesBodyweight: true, in: ctx)
        let s = WorkoutSummaryData.from(session: session)
        #expect(s.exercises.first?.usesBodyweight == true)
        #expect(abs((s.exercises.first?.topSetWeightKg ?? -1) - 0) <= 0.001)
    }

    @Test func swimSummaryShowsLaps() throws {
        let ctx = try makeContext()
        let start = Date(timeIntervalSince1970: 5000)
        let c = try WorkoutRepository.saveSwim(start: start, end: start.addingTimeInterval(900),
                                               laps: 18, targetLaps: 20, in: ctx)
        let s = WorkoutSummaryData.from(cardio: c)
        #expect(s.kind == .cardio)
        #expect(s.title == "Swim")
        #expect(s.laps == 18)
        #expect(s.targetLaps == 20)
        #expect(s.distanceM == nil)
    }

    // MARK: Cardio

    @Test func cardioSummaryPopulatesMetrics() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let end = start.addingTimeInterval(600)   // 10 minutes
        let c = CardioWorkout(type: .walk, start: start, end: end,
                              distance: 2000, activeEnergy: 120,
                              avgHeartRate: 110, maxHeartRate: 135)

        let s = WorkoutSummaryData.from(cardio: c)

        #expect(s.kind == .cardio)
        #expect(s.title == "Walk")
        #expect(s.date == start)
        #expect(abs(s.durationSec - 600) <= 0.001)   // end - start
        #expect(abs((s.distanceM ?? 0) - 2000) <= 0.001)
        // pace = 600s / 2km = 300 s/km
        #expect(abs((s.paceSecPerKm ?? 0) - 300) <= 0.001)
        #expect(abs((s.calories ?? 0) - 120) <= 0.001)
        #expect(abs((s.avgHR ?? 0) - 110) <= 0.001)
        #expect(abs((s.maxHR ?? 0) - 135) <= 0.001)

        // Strength fields empty/nil on a cardio summary.
        #expect(s.totalVolumeKg == nil)
        #expect(s.setCount == 0)
        #expect(s.exercises.isEmpty)
    }

    @Test func cardioSummaryCarriesHRAndRoute() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        let c = CardioWorkout(type: .run, start: start, end: start.addingTimeInterval(60), distance: 200)
        c.hrSamples = [HRSample(t: 10, bpm: 120, cardio: c), HRSample(t: 0, bpm: 100, cardio: c)]
        c.routeSamples = [RouteSample(t: 5, lat: 1, lon: 2, cardio: c),
                          RouteSample(t: 0, lat: 3, lon: 4, cardio: c)]

        let s = WorkoutSummaryData.from(cardio: c)
        // Ordered by t ascending.
        #expect(s.hr.map(\.t) == [0, 10])
        #expect(s.hr.map(\.bpm) == [100, 120])
        #expect(s.route.map(\.lat) == [3, 1])
        #expect(s.route.map(\.lon) == [4, 2])
    }

    @Test func cardioSummaryNilDistanceHasNilPace() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let c = CardioWorkout(type: .boxing, start: start, end: start.addingTimeInterval(300))
        let s = WorkoutSummaryData.from(cardio: c)
        #expect(s.distanceM == nil)
        #expect(s.paceSecPerKm == nil)
    }

    // MARK: Icons — the summary header glyph must match the history-list row

    @Test func cardioSummaryCarriesPerTypeSymbol() throws {
        // Every cardio type carries its own glyph (not a generic running icon), so the
        // summary header matches the history-list row.
        let start = Date(timeIntervalSince1970: 50_000)
        for type in CardioType.allCases {
            let c = CardioWorkout(type: type, start: start, end: start.addingTimeInterval(600))
            let s = WorkoutSummaryData.from(cardio: c)
            #expect(s.symbol == type.symbol, "\(type.rawValue) summary should use its own symbol")
        }
        // Spot-check the cases from the bug report.
        #expect(WorkoutSummaryData.from(cardio: CardioWorkout(type: .boxing, start: start, end: start)).symbol == "figure.boxing")
        #expect(WorkoutSummaryData.from(cardio: CardioWorkout(type: .swim, start: start, end: start)).symbol == "figure.pool.swim")
        #expect(WorkoutSummaryData.from(cardio: CardioWorkout(type: .walk, start: start, end: start)).symbol == "figure.walk")
    }

    @Test func strengthSummaryCarriesSessionSymbol() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Push Day", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        let s = WorkoutSummaryData.from(session: session)
        #expect(s.symbol == session.symbol, "strength summary mirrors the session's history glyph")
        #expect(s.symbol == "dumbbell")
    }

    // MARK: Feedback batch 6 — Other Cardio title, logged flag, warm/cool

    @Test func otherCardioUsesCustomTitle() throws {
        let start = Date(timeIntervalSince1970: 40_000)
        let c = CardioWorkout(type: .other, start: start, end: start.addingTimeInterval(1800),
                              customTitle: "Rowing")
        let s = WorkoutSummaryData.from(cardio: c)
        #expect(s.title == "Rowing", "free-text Other Cardio label wins over the type name")
    }

    @Test func otherCardioBlankCustomTitleFallsBackToTypeName() throws {
        let start = Date(timeIntervalSince1970: 41_000)
        let c = CardioWorkout(type: .other, start: start, end: start.addingTimeInterval(60),
                              customTitle: "   ")
        #expect(c.displayTitle == "Custom", "whitespace-only label is ignored")
        #expect(WorkoutSummaryData.from(cardio: c).title == "Custom")
    }

    @Test func loggedFlagFlowsThrough() throws {
        let start = Date(timeIntervalSince1970: 42_000)
        let logged = CardioWorkout(type: .run, start: start, end: start.addingTimeInterval(600), isLogged: true)
        #expect(WorkoutSummaryData.from(cardio: logged).isLogged)

        let live = CardioWorkout(type: .run, start: start, end: start.addingTimeInterval(600))
        #expect(!WorkoutSummaryData.from(cardio: live).isLogged)
    }

    @Test func strengthSummaryCarriesLoggedAndWarmCool() throws {
        let ctx = try makeContext()
        let start = Date(timeIntervalSince1970: 43_000)
        let session = try WorkoutRepository.createSession(title: "Logged Push", date: start, in: ctx)
        session.isLogged = true
        session.warmupSeconds = 180
        session.cooldownSeconds = 90
        let s = WorkoutSummaryData.from(session: session)
        #expect(s.isLogged)
        #expect(abs(s.warmupSec - 180) <= 0.001)
        #expect(abs(s.cooldownSec - 90) <= 0.001)
    }

    // The pure history glyph (feedback batch 6): CrossFit / bodyweight / weighted.
    @Test func sessionSymbolReflectsKind() throws {
        let ctx = try makeContext()
        let crossfit = try WorkoutRepository.createSession(title: "CrossFit – Fran", date: Date(), in: ctx)
        #expect(crossfit.symbol == "figure.strengthtraining.functional")

        let calisthenics = try WorkoutRepository.createSession(title: "Calisthenics", date: Date(), in: ctx)
        let pullup = try WorkoutRepository.findOrCreateExercise(named: "Pull-Up", in: ctx)
        _ = try WorkoutRepository.addSet(to: calisthenics, exercise: pullup, weightKg: 0, reps: 10,
                                         usesBodyweight: true, in: ctx)
        #expect(calisthenics.symbol == "figure.strengthtraining.traditional")

        let weights = try WorkoutRepository.createSession(title: "Push Day", date: Date(), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: weights, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        #expect(weights.symbol == "dumbbell")
    }

    // MARK: Read-only exercise detail — per-performer lines (field test 2026-08-18 #1)

    @Test func exerciseLinePutsMeFirst() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Bench", date: Date(timeIntervalSince1970: 8000), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        // The partner logs first: "Me" must still lead the performer list.
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 10, performedBy: sam, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)

        let line = try #require(WorkoutSummaryData.from(session: session).exercises.first)
        #expect(line.performers.map(\.name) == ["Me", "Sam"])
        #expect(line.performers.first?.isMe == true)
    }

    @Test func exerciseLineIncludesEachPartnerOnce() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Bench", date: Date(timeIntervalSince1970: 8100), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 10, performedBy: sam, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 65, reps: 8, performedBy: sam, in: ctx)

        let line = try #require(WorkoutSummaryData.from(session: session).exercises.first)
        #expect(line.performers.map(\.name) == ["Me", "Sam"])
        #expect(line.performers.last?.sets.count == 2)
    }

    @Test func partnersAppearInFirstAppearanceOrder() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Bench", date: Date(timeIntervalSince1970: 8200), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let zoe = try WorkoutRepository.findOrCreatePerson(named: "Zoe", in: ctx)
        let alex = try WorkoutRepository.findOrCreatePerson(named: "Alex", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 50, reps: 10, performedBy: zoe, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 70, reps: 8, performedBy: alex, in: ctx)

        let line = try #require(WorkoutSummaryData.from(session: session).exercises.first)
        // First appearance, not alphabetical.
        #expect(line.performers.map(\.name) == ["Me", "Zoe", "Alex"])
    }

    @Test func performerSetsAreInLoggedOrder() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Bench", date: Date(timeIntervalSince1970: 8300), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 12, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 85, reps: 10, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 90, reps: 8, in: ctx)

        let me = try #require(WorkoutSummaryData.from(session: session).exercises.first?.performers.first)
        #expect(me.sets.map(\.reps) == [12, 10, 8])
        #expect(me.sets.map(\.weightKg) == [80, 85, 90])
    }

    @Test func warmupSetsAreExcludedFromPerformerLines() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Bench", date: Date(timeIntervalSince1970: 8400), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 40, reps: 10, isWarmup: true, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)

        let me = try #require(WorkoutSummaryData.from(session: session).exercises.first?.performers.first)
        #expect(me.sets.map(\.reps) == [5])
    }

    @Test func soloSessionHasOneOwnerPerformerLine() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Squat", date: Date(timeIntervalSince1970: 8500), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 140, reps: 5, in: ctx)

        let line = try #require(WorkoutSummaryData.from(session: session).exercises.first)
        #expect(line.performers.count == 1)
        #expect(line.performers.first?.name == "Me")
    }

    @Test func bodyweightSetCarriesUsesBodyweightAndAddedLoad() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Pull", date: Date(timeIntervalSince1970: 8600), in: ctx)
        let pullup = try WorkoutRepository.findOrCreateExercise(named: "Pull-Up", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: pullup, weightKg: 10, reps: 8,
                                         usesBodyweight: true, in: ctx)

        let set = try #require(WorkoutSummaryData.from(session: session).exercises.first?.performers.first?.sets.first)
        #expect(set.usesBodyweight)
        #expect(abs(set.weightKg - 10) <= 0.001)
        #expect(set.reps == 8)
    }

    /// An exercise only a partner performed stays out of the owner's lines — the
    /// existing rule — so it has no performer detail either.
    @Test func exerciseWithOnlyPartnerSetsIsStillExcludedFromOwnerLines() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Bench", date: Date(timeIntervalSince1970: 8700), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let curl = try WorkoutRepository.findOrCreateExercise(named: "Barbell Curl", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: curl, weightKg: 30, reps: 12, performedBy: sam, in: ctx)

        let s = WorkoutSummaryData.from(session: session)
        #expect(s.exercises.map(\.name) == ["Bench Press"])
    }
}
#endif
