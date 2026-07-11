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
    // Phase 3 multi-system rules (2026-06-25 evidence upgrade).
    case strengthBlock      // goal-specific 4–8 week block target
    case volumeAdjust       // add/hold/reduce sets from personal response
    case periodizedVariation
    case aerobicBase        // easy/moderate base building
    case vo2Intervals       // long VO₂ intervals (4×4, etc.)
    case thresholdTempo      // tempo/threshold work
    case anaerobicOptIn     // SIT/short sprints — hard lane, preference-ranked
    case flexibility        // mobility/stretching
    case recoveryReadiness  // rest / easy / reduced-load from readiness or load
    case assessmentPrompt   // run/refresh a baseline for a system
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
    func prescribedSession(defaultSets: Int = 3, goal: TrainingGoal = .hypertrophy) -> PrescribedSession {
        guard kind != .cardioHIIT else {
            return PrescribedSession(title: cardioPrescription ?? "Interval session",
                                     exerciseNames: [],
                                     repLadder: [],
                                     loadKg: nil)
        }
        let sets = max(1, target?.sets ?? defaultSets)
        // When a rule pins an explicit single rep target (e.g. progression "hit
        // exactly N reps") that fixed target flattens across the sets — the ladder
        // never overrides a deliberate prescription. When the target carries a rep
        // *range* (e.g. deload 3–5), or no target at all, the coach prescribes a
        // productive descending pyramid across that range (issue 2), not a flat
        // low-bound dose.
        let ladder: [Int]
        if let t = target {
            if t.repsLow == t.repsHigh {
                ladder = Array(repeating: t.repsLow, count: sets)
            } else {
                ladder = RepLadder.ladder(low: t.repsLow, high: t.repsHigh, sets: sets)
            }
        } else {
            ladder = RepLadder.ladder(for: goal, sets: sets)
        }
        let names = exercise.map { [$0] } ?? defaultExerciseNames
        return PrescribedSession(title: prescribedTitle,
                                 exerciseNames: names,
                                 repLadder: ladder,
                                 loadKg: target?.loadKg)
    }

    /// When no specific exercise is named (goal-level recs like starter / add-volume),
    /// provide a sensible default so the logger doesn't open empty.
    private var defaultExerciseNames: [String] {
        if let part {
            return [Self.partDefaultExercise(part)]
        }
        // Full-body starter: three compound lifts.
        return ["Back Squat", "Bench Press", "Deadlift"]
    }

    /// A representative compound exercise for the given body part.
    static func partDefaultExercise(_ part: BodyPart) -> String {
        switch part {
        case .chest: return "Bench Press"
        case .back: return "Deadlift"
        case .shoulders: return "Overhead Press"
        case .legs: return "Back Squat"
        case .biceps: return "Barbell Curl"
        case .triceps: return "Tricep Dip"
        case .calves: return "Standing Calf Raise"
        case .abs: return "Plank"
        }
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
    public let citation: Citation   // primary citation — always present (D3)
    public let citationIds: [String]
    public let target: SetTarget?   // structured strength prescription, when applicable
    public let cardioPrescription: String?  // interval protocol name for cardioHIIT recs (P6)
    public let confidence: RecommendationConfidence
    public let priority: Int

    // MARK: Phase 3 multi-system metadata (optional; legacy rules leave them nil/empty).
    /// The physiological system this recommendation targets.
    public let system: TrainingSystem?
    /// The claim class — the citation(s) shown must come from this category's pool.
    public let evidenceCategory: EvidenceClaimCategory?
    /// Short "why now" facts (e.g. "VO₂ system hasn't been trained in 12 days").
    public let whyNowFacts: [String]
    /// Safety/risk notes the UI surfaces (e.g. stop for pain/dizziness).
    public let riskNotes: [String]
    /// Coaching uncertainty distinct from `confidence` (e.g. low when HRmax estimated).
    public let uncertainty: FactConfidence?
    /// Plain-language eligibility prerequisites (e.g. "aerobic base", "intermediate+").
    public let minimumEligibility: [String]

    public var allCitations: [Citation] {
        var result = [citation]
        for cid in citationIds {
            if let c = CitationRegistry.citation(forId: cid), c.id != citation.id {
                result.append(c)
            }
        }
        return result
    }

    public init(id: String,
                kind: RecommendationKind,
                part: BodyPart? = nil,
                exercise: String? = nil,
                title: String,
                action: String,
                detail: String,
                citation: Citation,
                citationIds: [String] = [],
                target: SetTarget? = nil,
                cardioPrescription: String? = nil,
                confidence: RecommendationConfidence,
                priority: Int,
                system: TrainingSystem? = nil,
                evidenceCategory: EvidenceClaimCategory? = nil,
                whyNowFacts: [String] = [],
                riskNotes: [String] = [],
                uncertainty: FactConfidence? = nil,
                minimumEligibility: [String] = []) {
        self.id = id
        self.kind = kind
        self.part = part
        self.exercise = exercise
        self.title = title
        self.action = action
        self.detail = detail
        self.citation = citation
        self.citationIds = citationIds
        self.target = target
        self.cardioPrescription = cardioPrescription
        self.confidence = confidence
        self.priority = priority
        self.system = system
        self.evidenceCategory = evidenceCategory
        self.whyNowFacts = whyNowFacts
        self.riskNotes = riskNotes
        self.uncertainty = uncertainty
        self.minimumEligibility = minimumEligibility
    }
}
