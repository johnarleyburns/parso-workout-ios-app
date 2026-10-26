import Foundation
import CadenceCore

/// Offline, deterministic Watch suggestion built from Watch-local completed sessions.
/// Always materializes a new plan; it never relaunches a previous workout.
public enum WatchLocalSuggestionGenerator {
    public enum Source: Equatable, Sendable { case watchHistory, starter, alreadyTrainedToday }

    public struct Result: Equatable, Sendable {
        public var source: Source
        public var plan: WatchPlanPayload
        public var exerciseLines: [String]
        public var prescriptionDetail: String
        public var launch: WatchLiftLaunch
    }

    static let starterPool = ["Bodyweight Squat", "Push-Up", "Plank", "Glute Bridge", "Reverse Lunge"]
    static let maxExercises = 4
    static let minExercises = 3

    private struct Candidate {
        var name: String
        var lastTrained: Date
        var reps: [Int]
        var weights: [Double]
    }

    public static func generate(sessions: [WorkoutSession], now: Date = Date(),
                                calendar: Calendar = .current) -> Result {
        let eligible = sessions.filter(WatchPreviousWorkout.isEligible).sorted {
            let a = WatchPreviousWorkout.completionDate($0), b = WatchPreviousWorkout.completionDate($1)
            if a != b { return a > b }
            return $0.id.uuidString < $1.id.uuidString
        }
        if let newest = eligible.first, calendar.isDate(WatchPreviousWorkout.completionDate(newest), inSameDayAs: now) {
            let title = "Already trained today"
            let plan = WatchPlanPayload(title: title, strength: .init(exerciseNames: [], repLadder: [], prescriptions: []))
            return Result(source: .alreadyTrainedToday, plan: plan,
                          exerciseLines: ["You already completed a strength workout today. Rest or take an easy walk."],
                          prescriptionDetail: "",
                          launch: WatchLiftLaunch(title: title, exerciseNames: [], repLadder: [], planPayload: plan))
        }

        func names(_ s: WorkoutSession) -> [String] {
            s.orderedSets.compactMap { set in
                guard !set.isWarmup, set.isOwnerSet, set.reps > 0 else { return nil }
                let n = set.exerciseNameSnapshot ?? set.exercise?.name ?? ""
                return n.isEmpty ? nil : n
            }
        }
        let excluded = Set(eligible.first.map(names) ?? [])

        var byName: [String: Candidate] = [:]
        for s in eligible {
            let date = WatchPreviousWorkout.completionDate(s)
            var seen = Set<String>()
            for set in s.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 {
                let n = set.exerciseNameSnapshot ?? set.exercise?.name ?? ""
                guard !n.isEmpty, !excluded.contains(n) else { continue }
                if byName[n] == nil { byName[n] = Candidate(name: n, lastTrained: date, reps: [], weights: []) }
                if seen.insert(n).inserted == false || byName[n]?.lastTrained == date {
                    // Only the newest session per movement supplies load/reps.
                    if byName[n]?.lastTrained == date {
                        byName[n]?.reps.append(set.reps)
                        byName[n]?.weights.append(set.weight)
                    }
                }
            }
        }
        var ranked = byName.values.sorted {
            $0.lastTrained != $1.lastTrained ? $0.lastTrained < $1.lastTrained : $0.name < $1.name
        }
        ranked = Array(ranked.prefix(maxExercises))

        var prescriptions: [PlannedExercisePrescription] = ranked.map { c in
            let count = min(3, max(2, c.reps.count))
            let reps = c.reps.sorted()[c.reps.count / 2]
            let weight = c.weights.max() ?? 0
            return PlannedExercisePrescription(exerciseName: c.name, sets: (0..<count).map { _ in
                PlannedSetPrescription(targetReps: reps, targetWeightKg: weight > 0 ? weight : nil)
            })
        }
        var source = Source.watchHistory
        if prescriptions.count < minExercises {
            if prescriptions.isEmpty { source = .starter }
            let used = Set(prescriptions.map(\.exerciseName)).union(excluded)
            var pool = starterPool.filter { !used.contains($0) }
            if pool.isEmpty { pool = starterPool }
            for n in pool where prescriptions.count < minExercises {
                prescriptions.append(PlannedExercisePrescription(
                    exerciseName: n, sets: (0..<3).map { _ in PlannedSetPrescription(targetReps: 10) }))
            }
        }
        let title = source == .starter ? "Starter Full Body" : "Suggested Strength"
        let exerciseNames = prescriptions.map(\.exerciseName)
        let ladder = prescriptions.first?.sets.map(\.targetReps) ?? []
        let plan = WatchPlanPayload(
            title: title, strength: .init(exerciseNames: exerciseNames, repLadder: ladder, prescriptions: prescriptions))
        let lines = prescriptions.map {
            "\($0.exerciseName) · \($0.sets.count)×\(WatchSuggestReview.repsText($0.sets.map(\.targetReps)))"
        }
        let total = prescriptions.reduce(0) { $0 + $1.sets.count }
        return Result(source: source, plan: plan, exerciseLines: lines,
                      prescriptionDetail: "\(total) working sets",
                      launch: WatchLiftLaunch(title: title, exerciseNames: exerciseNames,
                                              repLadder: ladder, planPayload: plan))
    }
}
