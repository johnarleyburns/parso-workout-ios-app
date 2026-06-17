import Foundation

/// How confident the engine is in a prescription. Strength/hypertrophy rules with
/// clear evidence are `high`/`moderate`; equivocal cases (e.g. endurance loading)
/// are `low` and labelled as such in the UI (D6 — honest, non-medical framing).
public enum RecommendationConfidence: Int, Sendable, Equatable, Comparable {
    case low
    case moderate
    case high
    public static func < (lhs: RecommendationConfidence, rhs: RecommendationConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    public var label: String {
        switch self {
        case .low:      return "lower confidence"
        case .moderate: return "moderate confidence"
        case .high:     return "well supported"
        }
    }
}

/// The rule family a recommendation came from (drives the leading SF Symbol / grouping
/// on the Coach card).
public enum RecommendationKind: String, Sendable, Equatable {
    case progression    // next-session load/reps via double progression
    case deload         // back off after a declining e1RM trend
    case addVolume      // add weekly sets toward the minimum effective range
    case starter        // cold-start: a sensible first session from goal/experience
    case cardioHIIT     // prescribed interval protocol from cardio assessment (P6)
}

/// A concrete, loggable target for the next time a lift (or a starter session) is
/// performed: how many sets, a rep range, an optional prescribed load (canonical
/// kilograms; nil = bodyweight / "any load"), and a target reps-in-reserve. This is
/// what "Do this workout" pre-fills into the logger in P5.2.
public struct SetTarget: Equatable, Sendable {
    public let sets: Int?           // suggested working sets (nil = keep current)
    public let repsLow: Int
    public let repsHigh: Int
    public let loadKg: Double?      // prescribed load in canonical kg (nil = bodyweight/any)
    public let rir: Int?            // target reps in reserve

    public init(sets: Int?, repsLow: Int, repsHigh: Int, loadKg: Double?, rir: Int?) {
        self.sets = sets
        self.repsLow = repsLow
        self.repsHigh = repsHigh
        self.loadKg = loadKg
        self.rir = rir
    }

    /// A compact one-line summary in the user's unit, e.g. "4×5 @ 102.5 kg · ≤2 RIR"
    /// or "3 sets · 6–12 reps · ≤1 RIR". Load renders only when prescribed.
    public func summary(unit: MeasurementUnitPreference) -> String {
        var head: String
        if repsLow == repsHigh {
            head = sets.map { "\($0)×\(repsLow)" } ?? "\(repsLow) reps"
        } else {
            head = sets.map { "\($0) sets · \(repsLow)–\(repsHigh) reps" } ?? "\(repsLow)–\(repsHigh) reps"
        }
        if let kg = loadKg {
            let value = WorkoutMath.display(kg, in: unit)
            let unitLabel = unit == .pounds ? "lb" : "kg"
            head += " @ \(SetTarget.trimmed(value)) \(unitLabel)"
        }
        if let rir = rir {
            head += " · ≤\(rir) RIR"
        }
        return head
    }

    /// Drops a trailing ".0" so whole loads read "100 kg", halves keep "102.5 kg".
    static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }
}

/// A concrete, loggable session blueprint derived from a coaching `Recommendation`
/// — the data "Do this workout" (P5.3) materializes into a `WorkoutSession` so the
/// logger opens pre-filled with the prescribed movement, planned sets, target reps,
/// and (where the engine prescribes one) the working load. Pure/derived so the
/// translation is `swift test`-verifiable; the app owns the SwiftData materialization.
public struct PrescribedSession: Equatable, Sendable {
    /// Session title (also the history row title), e.g. "Back Squat" or "Full-body session".
    public let title: String
    /// Prescribed movements, in order. Empty for goal-level prescriptions (starter /
    /// add-volume) where the engine names no specific lift — the user picks the
    /// movements and the rep ladder still applies.
    public let exerciseNames: [String]
    /// Target reps per planned set (length == the number of planned sets). Seeds the
    /// pending set rows and each new set's default reps.
    public let repLadder: [Int]
    /// Prescribed working load in canonical kilograms; nil = bodyweight / "any load"
    /// (the user supplies it).
    public let loadKg: Double?

    public init(title: String, exerciseNames: [String], repLadder: [Int], loadKg: Double?) {
        self.title = title
        self.exerciseNames = exerciseNames
        self.repLadder = repLadder
        self.loadKg = loadKg
    }
}

public extension Recommendation {
    /// Translates this recommendation into a concrete `PrescribedSession` for the
    /// "Do this workout" path (P5.3). Single-lift recs (progression / deload) name the
    /// movement and carry its prescribed load; goal-level recs (starter / add-volume)
    /// name no lift but still prescribe sets × reps the user applies to the movements
    /// they choose. CardioHIIT recs (P6) return an empty-session stub — the UI routes
    /// to the interval picker instead. `defaultSets` fills in when the target leaves
    /// the set count open (e.g. double-progression "keep your current sets").
    func prescribedSession(defaultSets: Int = 3) -> PrescribedSession {
        guard kind != .cardioHIIT else {
            return PrescribedSession(title: cardioPrescription ?? "Interval session",
                                     exerciseNames: [],
                                     repLadder: [],
                                     loadKg: nil)
        }
        let sets = max(1, target?.sets ?? defaultSets)
        // Start each planned set at the bottom of the prescribed rep range; double
        // progression climbs toward the top from there.
        let seedReps = target?.repsLow ?? 5
        let ladder = Array(repeating: seedReps, count: sets)
        let names = exercise.map { [$0] } ?? []
        return PrescribedSession(title: prescribedTitle,
                                 exerciseNames: names,
                                 repLadder: ladder,
                                 loadKg: target?.loadKg)
    }

    /// The session/history title for a "Do this workout" launch: the lift for a
    /// single-lift rec, the body part for an add-volume rec, else a neutral label.
    var prescribedTitle: String {
        if let exercise { return exercise }
        if kind == .starter { return "Full-body session" }
        if let part { return "\(part.displayName) focus" }
        return "Coach session"
    }
}

/// A single prescriptive coaching action derived from `TrainingFacts` — the P5
/// evolution of the read-only `Insight`. Like an insight it carries a mandatory
/// citation (D3) and a "why / the science" detail, but it also prescribes a concrete
/// next action and, where applicable, a structured `SetTarget` the logger can adopt.
public struct Recommendation: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: RecommendationKind
    public let part: BodyPart?      // the body part this concerns, if any
    public let exercise: String?    // the lift this concerns, if any
    public let title: String        // short headline, e.g. "Progress your squat"
    public let action: String       // the imperative one-liner, e.g. "Add a rep: 5×102.5 kg"
    public let detail: String       // the "why / the science" expansion
    public let citation: Citation   // always present (D3)
    public let target: SetTarget?   // structured strength prescription, when applicable
    public let cardioPrescription: String?  // interval protocol name for cardioHIIT recs (P6)
    public let confidence: RecommendationConfidence
    public let priority: Int        // ranking weight (higher first)

    public init(id: String,
                kind: RecommendationKind,
                part: BodyPart? = nil,
                exercise: String? = nil,
                title: String,
                action: String,
                detail: String,
                citation: Citation,
                target: SetTarget? = nil,
                cardioPrescription: String? = nil,
                confidence: RecommendationConfidence,
                priority: Int) {
        self.id = id
        self.kind = kind
        self.part = part
        self.exercise = exercise
        self.title = title
        self.action = action
        self.detail = detail
        self.citation = citation
        self.target = target
        self.cardioPrescription = cardioPrescription
        self.confidence = confidence
        self.priority = priority
    }
}
