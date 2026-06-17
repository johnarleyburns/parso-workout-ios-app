import Foundation
import SwiftData

// MARK: - Assessment model (strength-pivot P4)
//
// A coach measures. An `Assessment` is one result of a standardized, repeatable
// test the user runs over time so the engine can track progress longitudinally
// and (later, P5/P6) prescribe + re-test like a pre/post study. P4 ships the
// strength + strength-endurance battery; aerobic (VO₂max) and anaerobic (Wingate)
// kinds land in P6.
//
// CloudKit rules (REQUIREMENTS §7) hold: every stored property is optional or
// defaulted, no unique constraints, stable `id` + `updatedAt` + `originDevice`.

@Model
public final class Assessment {
    public var id: UUID = UUID()
    public var date: Date = Date()
    /// `AssessmentKind.rawValue`; stored as String for CloudKit friendliness.
    public var kind: String = AssessmentKind.pushupMax.rawValue
    /// The primary result in the kind's unit: estimated 1RM (kg), max reps, or
    /// hold time (seconds).
    public var value: Double = 0
    /// Raw test inputs so an estimate can be recomputed if equations improve: the
    /// load lifted (kg) for `e1RM`/`repMax`, and the reps achieved for `e1RM`.
    /// Zero for kinds that don't use them.
    public var inputWeight: Double = 0
    public var inputReps: Int = 0
    /// The lift this concerns, for `e1RM` / `repMax`; nil for bodyweight tests.
    public var exerciseName: String?
    /// The standardized protocol used (free text or a known protocol name).
    public var protocolName: String?
    public var notes: String?
    public var updatedAt: Date = Date()
    public var originDevice: String = ""

    public init(id: UUID = UUID(),
                date: Date = Date(),
                kind: AssessmentKind = .pushupMax,
                value: Double = 0,
                inputWeight: Double = 0,
                inputReps: Int = 0,
                exerciseName: String? = nil,
                protocolName: String? = nil,
                notes: String? = nil,
                updatedAt: Date = Date(),
                originDevice: String = "") {
        self.id = id
        self.date = date
        self.kind = kind.rawValue
        self.value = value
        self.inputWeight = inputWeight
        self.inputReps = inputReps
        self.exerciseName = exerciseName
        self.protocolName = protocolName
        self.notes = notes
        self.updatedAt = updatedAt
        self.originDevice = originDevice
    }

    public var kindValue: AssessmentKind {
        get { AssessmentKind(rawValue: kind) ?? .pushupMax }
        set { kind = newValue.rawValue }
    }

    /// Groups results that belong to the same longitudinal series: bodyweight
    /// tests group by kind alone; lift-specific tests group by kind + lift.
    public var seriesKey: String {
        kindValue.concernsLift ? "\(kind)::\(exerciseName ?? "")" : kind
    }
}

// MARK: - Taxonomy

/// What an assessment measures. P4 covers the strength + strength-endurance
/// battery; `vo2maxField` / `wingate` land in P6 (cardio/anaerobic).
public enum AssessmentKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case e1RM                 // estimated 1RM from a top set / AMRAP at load
    case repMax               // max reps at a fixed load (rep-max test)
    case pushupMax            // max strict push-ups
    case pullupMax            // max strict pull-ups
    case bodyweightSquatMax   // max bodyweight squats
    case plankHold            // max plank hold (seconds)
    case hollowHold           // max hollow-body hold (seconds)
    case vo2maxField          // estimated VO₂max from a field test (mL/kg/min)
    case wingate              // Wingate anaerobic peak power (watts)

    public var id: String { rawValue }

    public var category: AssessmentCategory {
        switch self {
        case .e1RM, .repMax: return .strength
        case .pushupMax, .pullupMax, .bodyweightSquatMax, .plankHold, .hollowHold:
            return .strengthEndurance
        case .vo2maxField, .wingate: return .cardio
        }
    }

    /// Unit of the stored `value`.
    public var unit: AssessmentUnit {
        switch self {
        case .e1RM: return .weightKg
        case .repMax, .pushupMax, .pullupMax, .bodyweightSquatMax: return .reps
        case .plankHold, .hollowHold: return .seconds
        case .vo2maxField: return .mlKgMin
        case .wingate: return .watts
        }
    }

    /// True when the result is tied to a specific lift (so series are per-lift).
    public var concernsLift: Bool {
        switch self {
        case .e1RM, .repMax: return true
        default: return false
        }
    }

    /// Higher is always better: heavier lift, more reps, longer hold, higher VO₂max,
    /// higher peak power. Explicit for the trend math.
    public var higherIsBetter: Bool { true }

    public var displayName: String {
        switch self {
        case .e1RM: return "Estimated 1RM test"
        case .repMax: return "Rep-max test"
        case .pushupMax: return "Max push-ups"
        case .pullupMax: return "Max pull-ups"
        case .bodyweightSquatMax: return "Max bodyweight squats"
        case .plankHold: return "Plank hold"
        case .hollowHold: return "Hollow-body hold"
        case .vo2maxField: return "VO₂max test"
        case .wingate: return "Wingate test"
        }
    }

    public var symbol: String {
        switch self {
        case .e1RM, .repMax: return "scalemass"
        case .pushupMax: return "figure.strengthtraining.functional"
        case .pullupMax: return "figure.play"
        case .bodyweightSquatMax: return "figure.cross.training"
        case .plankHold, .hollowHold: return "timer"
        case .vo2maxField: return "heart.text.clipboard"
        case .wingate: return "bolt.fill"
        }
    }

    /// Guided, app-presented protocol so the test set is standardized and trends
    /// aren't polluted (§04). Non-medical, conservative framing.
    public var protocolText: String {
        switch self {
        case .e1RM:
            return "Warm up thoroughly, then work up to a heavy single (or a hard set of 2–5 reps left in good form). Record the load and reps — your estimated 1RM is computed from them."
        case .repMax:
            return "Pick a fixed load you'll keep across re-tests. After a warm-up, do one all-out set with good form and record the reps."
        case .pushupMax:
            return "After a light warm-up, do as many strict push-ups as you can in one unbroken set. Chest to within a fist of the floor, full lockout, no rest at the top."
        case .pullupMax:
            return "Do as many strict, dead-hang pull-ups as you can in one set — full extension at the bottom, chin over the bar at the top, no kipping."
        case .bodyweightSquatMax:
            return "Do as many bodyweight squats as you can in one set at a steady cadence, hips below parallel each rep."
        case .plankHold:
            return "Hold a forearm plank with a flat back and braced core for as long as form stays solid. Stop the clock when your hips sag or rise."
        case .hollowHold:
            return "Lie on your back, lower back pressed down, legs and shoulders lifted into a hollow position. Hold as long as the lower back stays flat."
        case .vo2maxField:
            return "Run, walk, or cycle as far as you can in 12 minutes (Cooper test). Estimate your VO₂max from the distance covered — many online calculators and wearable devices provide this value in mL/kg/min."
        case .wingate:
            return "After a thorough warm-up, sprint all-out for 30 seconds against a fixed resistance (typically 7.5% of body weight on a cycle ergometer). Record the highest average power output (watts) achieved — most ergometers display this directly."
        }
    }
}

/// Which arm of the battery a kind belongs to (P4 ships strength + strength-endurance;
/// P6 adds cardio).
public enum AssessmentCategory: String, CaseIterable, Sendable, Identifiable {
    case strength
    case strengthEndurance
    case cardio
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .strengthEndurance: return "Strength-endurance"
        case .cardio: return "Cardio"
        }
    }
}

/// Unit of an assessment's stored value (drives formatting + which input the
/// record screen shows).
public enum AssessmentUnit: String, Sendable {
    case weightKg       // canonical kg (display-converted like other weights)
    case reps
    case seconds
    case mlKgMin        // mL/kg/min (VO₂max)
    case watts          // absolute watts (Wingate peak power)
}
