import Foundation
import Testing
@testable import CadenceCore

struct PRTimelineTests {

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    private func set(_ name: String, _ w: Double, _ r: Int, day n: Int, warmup: Bool = false) -> ExerciseSetSample {
        ExerciseSetSample(exerciseName: name,
                          sample: SetSample(weight: w, reps: r, date: day(n), isWarmup: warmup))
    }

    // MARK: - PRKind mapping stays 1:1 with PRRule

    @Test func pRKindMapsFromRule() {
        #expect(PRKind(rule: .topWeight) == .weight)
        #expect(PRKind(rule: .estimated1RM) == .e1RM)
        #expect(PRKind(rule: .topVolume) == .volume)
    }

    // MARK: - First-ever lift is a PR

    @Test func firstEverLiftIsAPR() {
        let events = PRTimeline.events(sets: [set("Squat", 100, 5, day: 1)],
                                       rule: .topWeight, formula: .epley)
        #expect(events.count == 1)
        #expect(events[0].exerciseName == "Squat")
        #expect(events[0].value == 100)
        #expect(events[0].previous == nil)
    }

    // MARK: - Ties are not PRs

    @Test func tieIsNotAPR() {
        let events = PRTimeline.events(sets: [
            set("Bench", 100, 5, day: 1),
            set("Bench", 100, 5, day: 2)   // exact tie — not a new record
        ], rule: .topWeight, formula: .epley)
        #expect(events.count == 1)
        #expect(events[0].date == day(1))
    }

    @Test func improvementIsAPRWithPrevious() {
        let events = PRTimeline.events(sets: [
            set("Bench", 100, 5, day: 1),
            set("Bench", 105, 5, day: 2)
        ], rule: .topWeight, formula: .epley)
        #expect(events.count == 2)
        #expect(events[1].value == 105)
        #expect(events[1].previous == 100)
    }

    // MARK: - A heavier single beats a lighter double on e1RM

    @Test func heavierSingleBeatsLighterDoubleOnE1RM() {
        // 100x1 → 100 ; 90x2 → 96 ; so the heavier single wins and is the only PR
        // when it comes second.
        let events = PRTimeline.events(sets: [
            set("Dead", 90, 2, day: 1),   // e1RM 96
            set("Dead", 100, 1, day: 2)   // e1RM 100 — improvement
        ], rule: .estimated1RM, formula: .epley)
        #expect(events.count == 2)
        #expect(abs(events[1].value - 100) <= 0.01)
    }

    // MARK: - Bodyweight lifts

    @Test func bodyweightLiftsCountWhenLoadPresent() {
        // Effective load is passed in already resolved; a positive load is a PR.
        let events = PRTimeline.events(sets: [set("Pull-up", 80, 8, day: 1)],
                                       rule: .topVolume, formula: .epley)
        #expect(events.count == 1)
        #expect(events[0].value == 640) // 80 * 8
    }

    // MARK: - Per-exercise independence

    @Test func squatPRDoesNotAffectBench() {
        let events = PRTimeline.events(sets: [
            set("Squat", 200, 3, day: 1),
            set("Bench", 60, 5, day: 2)   // far lighter, but still a first-ever bench PR
        ], rule: .topWeight, formula: .epley)
        #expect(events.count == 2)
        let bench = events.first { $0.exerciseName == "Bench" }
        #expect(bench != nil)
        #expect(bench?.previous == nil)
    }

    // MARK: - Chronological ordering

    @Test func eventsSortedChronologically() {
        let events = PRTimeline.events(sets: [
            set("Squat", 120, 5, day: 5),
            set("Squat", 100, 5, day: 1),
            set("Squat", 110, 5, day: 3)
        ], rule: .topWeight, formula: .epley)
        #expect(events.map(\.date) == [day(1), day(3), day(5)])
        #expect(events.map(\.value) == [100, 110, 120])
    }

    // MARK: - Warmup sets excluded

    @Test func warmupSetsExcluded() {
        let events = PRTimeline.events(sets: [
            set("OHP", 200, 1, day: 1, warmup: true),   // heaviest but a warmup
            set("OHP", 50, 5, day: 1)
        ], rule: .topWeight, formula: .epley)
        #expect(events.count == 1)
        #expect(events[0].value == 50)
    }

    // MARK: - latestPerExercise

    @Test func latestPerExerciseReturnsNewestPerLift() {
        let events = PRTimeline.latestPerExercise(sets: [
            set("Squat", 100, 5, day: 1),
            set("Squat", 110, 5, day: 3),  // latest squat PR
            set("Bench", 60, 5, day: 2)
        ], rule: .topWeight, formula: .epley)
        #expect(events.count == 2)
        let squat = events.first { $0.exerciseName == "Squat" }
        #expect(squat?.value == 110)
        #expect(squat?.date == day(3))
    }

    @Test func emptyInputProducesNoEvents() {
        #expect(PRTimeline.events(sets: [], rule: .topWeight, formula: .epley).isEmpty)
        #expect(PRTimeline.latestPerExercise(sets: [], rule: .topWeight, formula: .epley).isEmpty)
    }
}
