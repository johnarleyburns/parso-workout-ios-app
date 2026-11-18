import Foundation

// Field-testing §03 — a faceted exercise taxonomy (exrx-structured, original
// data). Equipment, mechanics, force, and a muscle catalog with scientific +
// colloquial synonyms power fast keyword search ("cable", "lats", "push").

/// How the user-entered weight maps to effective load for calculations.
/// Stored as a String on Exercise (default) and SetEntry (snapshot).
public enum LoadAccountingMode: String, CaseIterable, Codable, Sendable {
    case barbell            // entered = added plate load; effective = (entered + barWeight) * multiplier
    case bodyweight         // entered = added load only; effective = entered * multiplier
    case dualDumbbell       // entered total; no pairing multiplier
    case singleDumbbell     // entered = one dumbbell; effective = entered * 1
    case isolateralDumbbell // entered total; no comparison multiplier
    case dualKettlebell       // entered total; no pairing multiplier
    case singleKettlebell     // entered = one kettlebell; effective = entered * 1
    case isolateralKettlebell // entered total; no comparison multiplier
}

/// How the exercise is loaded (decision #11). Isolateral/unilateral is a
/// separate `isLateral` flag on the exercise so it composes with any equipment.
public enum Equipment: String, CaseIterable, Codable, Sendable, Identifiable {
    case barbell, dumbbell, cable, machine, bodyweight, plyometric, kettlebell, band, smith
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .barbell: return {
            #if os(Linux)
            "Barbell"
            #else
            String(localized: "Barbell", bundle: .module)
            #endif
        }()
        case .dumbbell: return {
            #if os(Linux)
            "Dumbbell"
            #else
            String(localized: "Dumbbell", bundle: .module)
            #endif
        }()
        case .cable: return {
            #if os(Linux)
            "Cable"
            #else
            String(localized: "Cable", bundle: .module)
            #endif
        }()
        case .machine: return {
            #if os(Linux)
            "Machine"
            #else
            String(localized: "Machine", bundle: .module)
            #endif
        }()
        case .bodyweight: return {
            #if os(Linux)
            "Bodyweight"
            #else
            String(localized: "Bodyweight", bundle: .module)
            #endif
        }()
        case .plyometric: return {
            #if os(Linux)
            "Plyometric"
            #else
            String(localized: "Plyometric", bundle: .module)
            #endif
        }()
        case .kettlebell: return {
            #if os(Linux)
            "Kettlebell"
            #else
            String(localized: "Kettlebell", bundle: .module)
            #endif
        }()
        case .band: return {
            #if os(Linux)
            "Band"
            #else
            String(localized: "Band", bundle: .module)
            #endif
        }()
        case .smith: return {
            #if os(Linux)
            "Smith Machine"
            #else
            String(localized: "Smith Machine", bundle: .module)
            #endif
        }()
        }
    }
}

/// Joint involvement (exrx "mechanics").
public enum Mechanics: String, CaseIterable, Codable, Sendable {
    case compound, isolation
}

/// Resistance direction (exrx "force"), distinct from the training-split
/// `ExerciseCategory`.
public enum Force: String, CaseIterable, Codable, Sendable {
    case push, pull, `static`
}

/// Broad body region for grouping/search. A display and ordering aid ONLY —
/// never a weekly-volume dimension. Collapsing volume onto regions is the
/// simplification `MuscleGroup` exists to remove (DB++ adoption, decision D2).
public enum BodyRegion: String, CaseIterable, Codable, Sendable {
    case chest, back, shoulders, arms, core, legs, glutes, fullBody
}

// MARK: free-exercise-db++ classification
//
// The three axes DB++ classifies every movement on. All three decode leniently:
// a value we do not know (from a future schema revision) is dropped rather than
// treated as fatal, because the bundled document is data, not code.

/// What kind of training a movement belongs to (DB++ `classification.trainingTypes`).
/// A movement can carry several — every powerlifting, Olympic and strongman entry
/// is also `strength`.
public enum ExerciseTrainingType: String, CaseIterable, Codable, Sendable {
    case strength
    case powerlifting
    case olympicWeightlifting = "olympic_weightlifting"
    case strongman
    case plyometrics
    case cardio
    case stretching
    case mobility

    public var displayName: String {
        switch self {
        case .strength: {
            #if os(Linux)
            "Strength"
            #else
            String(localized: "Strength", bundle: .module)
            #endif
        }()
        case .powerlifting: {
            #if os(Linux)
            "Powerlifting"
            #else
            String(localized: "Powerlifting", bundle: .module)
            #endif
        }()
        case .olympicWeightlifting: {
            #if os(Linux)
            "Olympic Weightlifting"
            #else
            String(localized: "Olympic Weightlifting", bundle: .module)
            #endif
        }()
        case .strongman: {
            #if os(Linux)
            "Strongman"
            #else
            String(localized: "Strongman", bundle: .module)
            #endif
        }()
        case .plyometrics: {
            #if os(Linux)
            "Plyometrics"
            #else
            String(localized: "Plyometrics", bundle: .module)
            #endif
        }()
        case .cardio: {
            #if os(Linux)
            "Cardio"
            #else
            String(localized: "Cardio", bundle: .module)
            #endif
        }()
        case .stretching: {
            #if os(Linux)
            "Stretching"
            #else
            String(localized: "Stretching", bundle: .module)
            #endif
        }()
        case .mobility: {
            #if os(Linux)
            "Mobility"
            #else
            String(localized: "Mobility", bundle: .module)
            #endif
        }()
        }
    }

    /// Some upstream records use the broad `strength` category even when their
    /// name is an Olympic lift. Keep the suggestion policy stable across those
    /// records and across older persisted Exercise rows.
    public static func isOlympicOnlyMovement(named name: String) -> Bool {
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
        return normalized.contains("snatch")
            || normalized.contains("clean and jerk")
            || normalized.contains("clean and press")
    }

    /// Drops values this build does not know rather than failing the decode.
    public static func decode(_ values: [String]) -> [ExerciseTrainingType] {
        values.compactMap(ExerciseTrainingType.init(rawValue:))
    }
}

/// How a movement is loaded (DB++ `classification.modalities`). Distinct from our
/// `Equipment`, which is a narrower facet used for search and load accounting.
public enum ExerciseModality: String, CaseIterable, Codable, Sendable {
    case bodyweight
    case freeWeight = "free_weight"
    case machine
    case cable
    case band
    case kettlebell
    case medicineBall = "medicine_ball"
    case loadedObject = "loaded_object"
    case sled
    case rope
    case foamRoll = "foam_roll"
    case other

    public var displayName: String {
        switch self {
        case .bodyweight: {
            #if os(Linux)
            "Bodyweight"
            #else
            String(localized: "Bodyweight", bundle: .module)
            #endif
        }()
        case .freeWeight: {
            #if os(Linux)
            "Free Weight"
            #else
            String(localized: "Free Weight", bundle: .module)
            #endif
        }()
        case .machine: {
            #if os(Linux)
            "Machine"
            #else
            String(localized: "Machine", bundle: .module)
            #endif
        }()
        case .cable: {
            #if os(Linux)
            "Cable"
            #else
            String(localized: "Cable", bundle: .module)
            #endif
        }()
        case .band: {
            #if os(Linux)
            "Band"
            #else
            String(localized: "Band", bundle: .module)
            #endif
        }()
        case .kettlebell: {
            #if os(Linux)
            "Kettlebell"
            #else
            String(localized: "Kettlebell", bundle: .module)
            #endif
        }()
        case .medicineBall: {
            #if os(Linux)
            "Medicine Ball"
            #else
            String(localized: "Medicine Ball", bundle: .module)
            #endif
        }()
        case .loadedObject: {
            #if os(Linux)
            "Loaded Object"
            #else
            String(localized: "Loaded Object", bundle: .module)
            #endif
        }()
        case .sled: {
            #if os(Linux)
            "Sled"
            #else
            String(localized: "Sled", bundle: .module)
            #endif
        }()
        case .rope: {
            #if os(Linux)
            "Rope"
            #else
            String(localized: "Rope", bundle: .module)
            #endif
        }()
        case .foamRoll: {
            #if os(Linux)
            "Foam Roll"
            #else
            String(localized: "Foam Roll", bundle: .module)
            #endif
        }()
        case .other: {
            #if os(Linux)
            "Other"
            #else
            String(localized: "Other", bundle: .module)
            #endif
        }()
        }
    }

    public static func decode(_ values: [String]) -> [ExerciseModality] {
        values.compactMap(ExerciseModality.init(rawValue:))
    }

    /// The modality implied by one of our `Equipment` facets, for curated entries
    /// that have no DB++ counterpart.
    public static func implied(by equipment: Equipment?) -> [ExerciseModality] {
        switch equipment {
        case .barbell, .dumbbell, .smith: [.freeWeight]
        case .cable: [.cable]
        case .machine: [.machine]
        case .bodyweight, .plyometric: [.bodyweight]
        case .band: [.band]
        case .kettlebell: [.kettlebell]
        case nil: [.other]
        }
    }
}

/// The sport a movement belongs to (DB++ `classification.sportContexts`). Every
/// movement carries `generalFitness`; sport entries carry theirs in addition.
public enum ExerciseSportContext: String, CaseIterable, Codable, Sendable {
    case powerlifting
    case weightlifting
    case strongman
    case crossfit
    case gymnastics
    case generalFitness = "general_fitness"

    public var displayName: String {
        switch self {
        case .powerlifting: {
            #if os(Linux)
            "Powerlifting"
            #else
            String(localized: "Powerlifting", bundle: .module)
            #endif
        }()
        case .weightlifting: {
            #if os(Linux)
            "Weightlifting"
            #else
            String(localized: "Weightlifting", bundle: .module)
            #endif
        }()
        case .strongman: {
            #if os(Linux)
            "Strongman"
            #else
            String(localized: "Strongman", bundle: .module)
            #endif
        }()
        case .crossfit: "CrossFit"
        case .gymnastics: {
            #if os(Linux)
            "Gymnastics"
            #else
            String(localized: "Gymnastics", bundle: .module)
            #endif
        }()
        case .generalFitness: {
            #if os(Linux)
            "General Fitness"
            #else
            String(localized: "General Fitness", bundle: .module)
            #endif
        }()
        }
    }

    public static func decode(_ values: [String]) -> [ExerciseSportContext] {
        values.compactMap(ExerciseSportContext.init(rawValue:))
    }
}

/// How confident DB++ is in a movement's muscle-role annotation. `nil` on an
/// exercise means the roles are our own mapping, not a DB++ annotation at all.
public enum AnnotationConfidence: String, CaseIterable, Codable, Sendable {
    case high, medium, low

    public var displayName: String {
        switch self {
        case .high: {
            #if os(Linux)
            "High"
            #else
            String(localized: "High", bundle: .module)
            #endif
        }()
        case .medium: {
            #if os(Linux)
            "Medium"
            #else
            String(localized: "Medium", bundle: .module)
            #endif
        }()
        case .low: {
            #if os(Linux)
            "Low"
            #else
            String(localized: "Low", bundle: .module)
            #endif
        }()
        }
    }
}
