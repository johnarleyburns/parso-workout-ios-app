import Foundation

/// A single all-time personal-record moment on a lift's timeline (FR-5.2). Pure;
/// built from `SetSample`s so the timeline, the in-session PR badge, and
/// `WorkoutRepository.wouldBePR` all resolve a PR the same way — they share
/// `PRCalculator`, so they can never disagree.
public struct PREvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let exerciseName: String
    public let date: Date
    public let kind: PRKind
    public let value: Double        // metric value under the rule (canonical kg / kg·reps)
    public let reps: Int            // the reps of the set that set the record
    public let weightKg: Double     // the effective load of the set that set the record
    public let previous: Double?    // the prior all-time best under the rule, if any

    public init(id: UUID = UUID(), exerciseName: String, date: Date, kind: PRKind,
                value: Double, reps: Int, weightKg: Double, previous: Double?) {
        self.id = id
        self.exerciseName = exerciseName
        self.date = date
        self.kind = kind
        self.value = value
        self.reps = reps
        self.weightKg = weightKg
        self.previous = previous
    }
}

/// The record type, kept 1:1 with `PRRule` so the timeline never defines a PR
/// differently from the rest of the app.
public enum PRKind: String, Sendable, Equatable, Codable {
    case weight     // heaviest weight lifted
    case e1RM       // best estimated 1RM
    case volume     // best single-set volume (weight × reps)

    public init(rule: PRRule) {
        switch rule {
        case .topWeight:    self = .weight
        case .estimated1RM: self = .e1RM
        case .topVolume:    self = .volume
        }
    }
}

/// One exercise's set, flattened for pure PR math (no SwiftData). The app builds
/// these off `WorkoutSession` history via `WorkoutRepository.prEvents`.
public struct ExerciseSetSample: Sendable, Equatable {
    public let exerciseName: String
    public let sample: SetSample

    public init(exerciseName: String, sample: SetSample) {
        self.exerciseName = exerciseName
        self.sample = sample
    }
}

public enum PRTimeline {

    /// Every set that set a new all-time record for its exercise under `rule`,
    /// ascending by date. Warmups and empty sets are ignored (`PRCalculator`).
    /// A first-ever working set on a lift is a PR (`previous == nil`); a tie is
    /// NOT a PR (must strictly exceed, matching `PRCalculator.isNewPR`).
    public static func events(sets: [ExerciseSetSample],
                              rule: PRRule,
                              formula: OneRepMaxFormula) -> [PREvent] {
        let byExercise = Dictionary(grouping: sets, by: { $0.exerciseName })
        var out: [PREvent] = []
        for (name, group) in byExercise {
            let samples = group
                .map { $0.sample }
                .filter { !$0.isWarmup && $0.reps > 0 && $0.weight > 0 }
                .sorted { $0.date < $1.date }
            var best: Double? = nil
            for s in samples {
                let v = PRCalculator.metric(s, rule: rule, formula: formula)
                if let prior = best, v <= prior + 1e-9 { continue }
                out.append(PREvent(exerciseName: name, date: s.date, kind: PRKind(rule: rule),
                                   value: v, reps: s.reps, weightKg: s.weight, previous: best))
                best = v
            }
        }
        return out.sorted {
            $0.date != $1.date ? $0.date < $1.date
                               : $0.exerciseName < $1.exerciseName
        }
    }

    /// The most recent PR per exercise, newest first — the "trophy shelf" the
    /// share card draws from.
    public static func latestPerExercise(sets: [ExerciseSetSample],
                                         rule: PRRule,
                                         formula: OneRepMaxFormula) -> [PREvent] {
        let all = events(sets: sets, rule: rule, formula: formula)
        var latest: [String: PREvent] = [:]
        for e in all {
            if let existing = latest[e.exerciseName], existing.date >= e.date { continue }
            latest[e.exerciseName] = e
        }
        return latest.values.sorted {
            $0.date != $1.date ? $0.date > $1.date
                               : $0.exerciseName < $1.exerciseName
        }
    }
}
