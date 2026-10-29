import Foundation

/// Pure, table-driven policy deciding whether a third-party HealthKit workout
/// becomes a Cladiron cardio history row. Keyed by the raw
/// `HKWorkoutActivityType` value so it stays headlessly testable. Unknown
/// (including future) activity types are excluded and reported, never guessed.
public struct HealthKitCardioEligibility: Equatable, Sendable {
    public let rawActivityType: UInt
    public let activityName: String
    public let cardioType: CardioType
    public let importedKind: ImportedWorkoutKind

    public enum Decision: Equatable, Sendable {
        case eligible(HealthKitCardioEligibility)
        case excluded(reason: String)

        public var eligibility: HealthKitCardioEligibility? {
            if case .eligible(let value) = self { return value }
            return nil
        }
    }

    private struct Row {
        let name: String
        let cardio: CardioType
        let kind: ImportedWorkoutKind
    }

    private static func aerobic(_ name: String, _ cardio: CardioType,
                                _ kind: ImportedWorkoutKind) -> Row {
        Row(name: name, cardio: cardio, kind: kind)
    }

    /// Recognised aerobic activities (HKWorkoutActivityType raw values).
    private static let cardioTable: [UInt: Row] = [
        37: aerobic("running", .run, .running),
        52: aerobic("walking", .walk, .walking),
        24: aerobic("hiking", .walk, .walking),
        13: aerobic("cycling", .cycle, .cycling),
        74: aerobic("handCycling", .cycle, .cycling),
        46: aerobic("swimming", .swim, .swimming),
        35: aerobic("rowing", .rowing, .rowing),
        63: aerobic("highIntensityIntervalTraining", .hiit, .hiit),
        8: aerobic("boxing", .boxing, .boxing),
        28: aerobic("martialArts", .boxing, .boxing),
        16: aerobic("elliptical", .elliptical, .other),
        44: aerobic("stairClimbing", .stairClimber, .other),
        68: aerobic("stairs", .stairClimber, .other),
        69: aerobic("stepTraining", .stairClimber, .other),
        // Other cardio
        11: aerobic("crossTraining", .other, .other),
        64: aerobic("jumpRope", .other, .other),
        65: aerobic("kickboxing", .other, .other),
        73: aerobic("mixedCardio", .other, .other),
        30: aerobic("mixedMetabolicCardioTraining", .other, .other),
        77: aerobic("cardioDance", .other, .other),
        14: aerobic("dance", .other, .other),
        53: aerobic("waterFitness", .other, .other),
        60: aerobic("crossCountrySkiing", .other, .other),
        82: aerobic("swimBikeRun", .other, .other),
        70: aerobic("wheelchairWalkPace", .walk, .walking),
        71: aerobic("wheelchairRunPace", .run, .running),
    ]

    /// Known categories deliberately not imported as cardio.
    private static let excludedTable: [UInt: String] = [
        50: "traditionalStrengthTraining",
        20: "functionalStrengthTraining",
        59: "coreTraining",
        62: "flexibility",
        57: "yoga",
        66: "pilates",
        58: "barre",
        72: "taiChi",
        29: "mindAndBody",
        33: "preparationAndRecovery",
        80: "cooldown",
        83: "transition",
    ]

    public static func evaluate(rawActivityType raw: UInt) -> Decision {
        if let row = cardioTable[raw] {
            return .eligible(HealthKitCardioEligibility(
                rawActivityType: raw, activityName: row.name,
                cardioType: row.cardio, importedKind: row.kind))
        }
        if let name = excludedTable[raw] {
            return .excluded(reason: "Excluded non-cardio activity: \(name)")
        }
        return .excluded(reason: "Unrecognized activity type \(raw); not imported")
    }

    /// Exact Cladiron ownership (phone app and embedded Watch app only).
    public static let cladironPhoneBundleID = "guru.parso.ios-workout-app"
    public static let cladironWatchBundleID = "guru.parso.ios-workout-app.watchkitapp"

    public static func isCladironAuthored(bundleIdentifier: String) -> Bool {
        bundleIdentifier == cladironPhoneBundleID || bundleIdentifier == cladironWatchBundleID
    }
}
