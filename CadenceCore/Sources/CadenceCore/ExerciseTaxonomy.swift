import Foundation

// Field-testing §03 — a faceted exercise taxonomy (exrx-structured, original
// data). Equipment, mechanics, force, and a muscle catalog with scientific +
// colloquial synonyms power fast keyword search ("cable", "lats", "push").

/// How the user-entered weight maps to effective load for calculations.
/// Stored as a String on Exercise (default) and SetEntry (snapshot).
public enum LoadAccountingMode: String, CaseIterable, Codable, Sendable {
    case barbell            // entered = added plate load; effective = (entered + barWeight) * multiplier
    case bodyweight         // entered = added load only; effective = entered * multiplier
    case dualDumbbell       // entered = one dumbbell; effective = entered * 2
    case singleDumbbell     // entered = one dumbbell; effective = entered * 1
    case isolateralDumbbell // entered = one dumbbell; effective = entered * 2 (comparison mode)
    case dualKettlebell       // entered = one kettlebell; effective = entered * 2
    case singleKettlebell     // entered = one kettlebell; effective = entered * 1
    case isolateralKettlebell // entered = one kettlebell; effective = entered * 2 (comparison mode)
}

/// How the exercise is loaded (decision #11). Isolateral/unilateral is a
/// separate `isLateral` flag on the exercise so it composes with any equipment.
public enum Equipment: String, CaseIterable, Codable, Sendable, Identifiable {
    case barbell, dumbbell, cable, machine, bodyweight, plyometric, kettlebell, band, smith
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .cable: return "Cable"
        case .machine: return "Machine"
        case .bodyweight: return "Bodyweight"
        case .plyometric: return "Plyometric"
        case .kettlebell: return "Kettlebell"
        case .band: return "Band"
        case .smith: return "Smith Machine"
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
        case .strength: "Strength"
        case .powerlifting: "Powerlifting"
        case .olympicWeightlifting: "Olympic Weightlifting"
        case .strongman: "Strongman"
        case .plyometrics: "Plyometrics"
        case .cardio: "Cardio"
        case .stretching: "Stretching"
        case .mobility: "Mobility"
        }
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
        case .bodyweight: "Bodyweight"
        case .freeWeight: "Free Weight"
        case .machine: "Machine"
        case .cable: "Cable"
        case .band: "Band"
        case .kettlebell: "Kettlebell"
        case .medicineBall: "Medicine Ball"
        case .loadedObject: "Loaded Object"
        case .sled: "Sled"
        case .rope: "Rope"
        case .foamRoll: "Foam Roll"
        case .other: "Other"
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
        case .powerlifting: "Powerlifting"
        case .weightlifting: "Weightlifting"
        case .strongman: "Strongman"
        case .crossfit: "CrossFit"
        case .gymnastics: "Gymnastics"
        case .generalFitness: "General Fitness"
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
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}
