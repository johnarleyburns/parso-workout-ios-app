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

    public var inputDistance: Double?
    public var inputTime: Double?
    public var inputEndingHR: Double?
    public var inputAge: Int?
    public var inputSex: Int?

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
                originDevice: String = "",
                inputDistance: Double? = nil,
                inputTime: Double? = nil,
                inputEndingHR: Double? = nil,
                inputAge: Int? = nil,
                inputSex: Int? = nil) {
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
        self.inputDistance = inputDistance
        self.inputTime = inputTime
        self.inputEndingHR = inputEndingHR
        self.inputAge = inputAge
        self.inputSex = inputSex
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
    case e1RM
    case repMax
    case pushupMax
    case pullupMax
    case bodyweightSquatMax
    case plankHold
    case hollowHold
    case vo2maxField
    case cooper12min
    case run1_5mile
    case rockportWalk
    case queensCollegeStep
    case wingate

    public var id: String { rawValue }

    public var category: AssessmentCategory {
        switch self {
        case .e1RM, .repMax: return .strength
        case .pushupMax, .pullupMax, .bodyweightSquatMax, .plankHold, .hollowHold:
            return .strengthEndurance
        case .vo2maxField, .cooper12min, .run1_5mile, .rockportWalk, .queensCollegeStep, .wingate:
            return .cardio
        }
    }

    public var unit: AssessmentUnit {
        switch self {
        case .e1RM: return .weightKg
        case .repMax, .pushupMax, .pullupMax, .bodyweightSquatMax: return .reps
        case .plankHold, .hollowHold: return .seconds
        case .vo2maxField, .cooper12min, .run1_5mile, .rockportWalk, .queensCollegeStep: return .mlKgMin
        case .wingate: return .watts
        }
    }

    public var concernsLift: Bool {
        switch self {
        case .e1RM, .repMax: return true
        default: return false
        }
    }

    public var higherIsBetter: Bool { true }

    public var isAdvanced: Bool {
        switch self {
        case .wingate: return true
        default: return false
        }
    }

    /// Kinds shown in the default battery (excludes advanced tests that need lab gear).
    public static var defaultBattery: [AssessmentKind] {
        allCases.filter { !$0.isAdvanced }
    }

    public var displayName: String {
        switch self {
        case .e1RM: return String(localized: "Estimated 1RM test", bundle: .module)
        case .repMax: return String(localized: "Rep-max test", bundle: .module)
        case .pushupMax: return String(localized: "Max push-ups", bundle: .module)
        case .pullupMax: return String(localized: "Max pull-ups", bundle: .module)
        case .bodyweightSquatMax: return String(localized: "Max bodyweight squats", bundle: .module)
        case .plankHold: return String(localized: "Plank hold", bundle: .module)
        case .hollowHold: return String(localized: "Hollow-body hold", bundle: .module)
        case .vo2maxField: return "VO\u{2082}max (manual entry)"
        case .cooper12min: return String(localized: "Cooper 12-min run", bundle: .module)
        case .run1_5mile: return "1.5-mile run"
        case .rockportWalk: return String(localized: "Rockport 1-mile walk", bundle: .module)
        case .queensCollegeStep: return String(localized: "Queens College step test", bundle: .module)
        case .wingate: return String(localized: "Wingate test", bundle: .module)
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
        case .cooper12min: return "figure.run"
        case .run1_5mile: return "figure.run"
        case .rockportWalk: return "figure.walk"
        case .queensCollegeStep: return "figure.step.training"
        case .wingate: return "bolt.fill"
        }
    }

    public var protocolText: String {
        switch self {
        case .e1RM:
            return String(localized: "Warm up thoroughly, then work up to a heavy single (or a hard set of 2\u{2013}5 reps left in good form). Record the load and reps \u{2014} your estimated 1RM is computed from them.", bundle: .module)
        case .repMax:
            return String(localized: "Pick a fixed load you\u{2019}ll keep across re-tests. After a warm-up, do one all-out set with good form and record the reps.", bundle: .module)
        case .pushupMax:
            return String(localized: "After a light warm-up, do as many strict push-ups as you can in one unbroken set. Chest to within a fist of the floor, full lockout, no rest at the top.", bundle: .module)
        case .pullupMax:
            return String(localized: "Do as many strict, dead-hang pull-ups as you can in one set \u{2014} full extension at the bottom, chin over the bar at the top, no kipping.", bundle: .module)
        case .bodyweightSquatMax:
            return String(localized: "Do as many bodyweight squats as you can in one set at a steady cadence, hips below parallel each rep.", bundle: .module)
        case .plankHold:
            return String(localized: "Hold a forearm plank with a flat back and braced core for as long as form stays solid. Stop the clock when your hips sag or rise.", bundle: .module)
        case .hollowHold:
            return String(localized: "Lie on your back, lower back pressed down, legs and shoulders lifted into a hollow position. Hold as long as the lower back stays flat.", bundle: .module)
        case .vo2maxField:
            return String(localized: "Enter your VO\u{2082}max value from a wearable device or lab test (mL/kg/min). For an on-device estimate, use the Cooper 12-min run, 1.5-mile run, or Rockport walk tests instead.", bundle: .module)
        case .cooper12min:
            return String(localized: "Warm up for 5\u{2013}10 minutes with light jogging. Then run as far as you can in exactly 12 minutes on a flat track or field. Record the total distance in meters. Your VO\u{2082}max is computed as (distance \u{2212} 504.9) \u{00f7} 44.73.", bundle: .module)
        case .run1_5mile:
            return String(localized: "Warm up for 5\u{2013}10 minutes. Run 1.5 miles (2.4 km) as fast as you can on a flat course. Record your time. Your VO\u{2082}max is computed as 483 \u{00f7} time (minutes) + 3.5.", bundle: .module)
        case .rockportWalk:
            return String(localized: "Walk 1 mile (1.6 km) as fast as you can on a flat course. Immediately after finishing, record your walk time and your heart rate (use a chest strap or take a 15-second pulse \u{00d7} 4). The app computes your VO\u{2082}max from your age, sex, weight, walk time, and ending heart rate (Kline et al. 1987).", bundle: .module)
        case .queensCollegeStep:
            return String(localized: "Step up and down on a 16.25-inch (41.3 cm) bench for 3 minutes at a steady cadence: 24 steps/min for men, 22 steps/min for women. Immediately after, count your pulse for 15 seconds (starting 5 seconds post-exercise) and multiply by 4 to get recovery HR. The app computes your VO\u{2082}max (McArdle et al. 1972).", bundle: .module)
        case .wingate:
            return String(localized: "Advanced \u{2014} requires a cycle ergometer. After a thorough warm-up, sprint all-out for 30 seconds against a fixed resistance (typically 7.5% of body weight). Record the highest average power output (watts).", bundle: .module)
        }
    }

    /// The evidence backing this test and the honesty caveat the UI must show. Every
    /// kind resolves to a policy — bodyweight endurance tests with no defensible
    /// population-validity source are explicit `personalBenchmark`s rather than
    /// returning no citations (the prior gap for push-up/pull-up/squat/hold tests).
    public var evidencePolicy: AssessmentEvidencePolicy {
        switch self {
        case .e1RM, .repMax:
            return .validated(citationIds: ["oneRMEstimation"])
        case .cooper12min, .run1_5mile:
            // Cooper (1968) validated the 12-min / 1.5-mile field run vs treadmill VO₂max.
            return .fieldEstimate(citationIds: ["cooperVo2max"], uncertainty: .moderate)
        case .rockportWalk:
            return .fieldEstimate(citationIds: ["rockportWalk"], uncertainty: .moderate)
        case .queensCollegeStep:
            return .fieldEstimate(citationIds: ["queensCollegeStep"], uncertainty: .moderate)
        case .vo2maxField:
            // Manually entered from a wearable/lab — validity depends on its source.
            return .fieldEstimate(citationIds: ["fieldFitnessReliability2022"], uncertainty: .low)
        case .wingate:
            return .validated(citationIds: ["wingateTest"])
        case .plankHold:
            // Tong et al. (2014) validated a global core-endurance plank test.
            return .fieldEstimate(citationIds: ["tongPlank2014"], uncertainty: .moderate)
        case .pushupMax, .pullupMax, .bodyweightSquatMax, .hollowHold:
            return .personalBenchmark(
                citationIds: ["fieldFitnessReliability2022"],
                caveat: String(localized: "Tracked as a personal benchmark — no population-validated equation maps this to a lab measure. Compare yourself to yourself over time.", bundle: .module))
        }
    }

    public var citationIds: [String] { evidencePolicy.citationIds }
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
        case .strengthEndurance: return String(localized: "Strength-endurance", bundle: .module)
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

/// How much published validity backs a given assessment, and the honesty caveat the
/// UI must show (2026-06-25 evidence upgrade). Every `AssessmentKind` resolves to one
/// of these so Coach never presents a bodyweight benchmark as a lab-grade measure.
public enum AssessmentEvidencePolicy: Sendable, Equatable {
    /// A protocol/equation validated against a reference standard in published work.
    case validated(citationIds: [String])
    /// A field estimate of a physiological quantity, with explicit uncertainty.
    case fieldEstimate(citationIds: [String], uncertainty: FactConfidence)
    /// A self-tracked benchmark with no population-validity claim; compare to yourself.
    case personalBenchmark(citationIds: [String], caveat: String)

    public var citationIds: [String] {
        switch self {
        case .validated(let ids): return ids
        case .fieldEstimate(let ids, _): return ids
        case .personalBenchmark(let ids, _): return ids
        }
    }

    /// Coaching uncertainty implied by the policy: validated = moderate, field = its
    /// declared level, personal benchmark = low.
    public var uncertainty: FactConfidence {
        switch self {
        case .validated: return .moderate
        case .fieldEstimate(_, let u): return u
        case .personalBenchmark: return .low
        }
    }

    public var caveat: String? {
        if case .personalBenchmark(_, let caveat) = self { return caveat }
        return nil
    }
}
