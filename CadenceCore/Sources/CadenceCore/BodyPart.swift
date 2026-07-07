import Foundation

/// The eight body parts surfaced on Home's "body parts this week" coverage tile
/// (feedback batch 3). Distinct from the fine-grained `MuscleCatalog`: this is a
/// coarse, user-facing grouping the user named — with "shoulders" in place of the
/// originally-listed "neck" (no neck movements exist; shoulders are trained often).
public enum BodyPart: String, CaseIterable, Sendable, Identifiable, Codable {
    case legs, back, chest, shoulders, biceps, triceps, calves, abs

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .legs: return "Legs"
        case .back: return "Back"
        case .chest: return "Chest"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .calves: return "Calves"
        case .abs: return "Abs"
        }
    }

    /// Maps a fine-grained `MuscleCatalog` id to its coarse body part, if any.
    /// Forearms/grip and hip-flexors-only work map to legs where appropriate;
    /// muscles with no coarse bucket (e.g. forearms) return nil and don't count.
    public static func part(forMuscleID id: String) -> BodyPart? {
        switch id {
        case "chest", "upper-chest": return .chest
        case "lats", "traps", "rhomboids", "lower-back": return .back
        case "delts", "front-delts", "rear-delts": return .shoulders
        case "biceps": return .biceps
        case "triceps": return .triceps
        case "calves": return .calves
        case "abs", "obliques": return .abs
        case "quads", "quadriceps", "hamstrings", "glutes", "adductors", "abductors", "hip-flexors":
            return .legs
        default: return nil
        }
    }

    /// The body parts hit by one exercise, given its muscle ids (primary + secondary).
    public static func parts(forMuscleIDs ids: [String]) -> Set<BodyPart> {
        Set(ids.compactMap(part(forMuscleID:)))
    }

    /// Coverage across a week's exercises: each element is one exercise's muscle
    /// ids (primary + secondary). Returns the parts hit and the parts missing
    /// (missing in canonical `allCases` order, for a stable display).
    public static func coverage(forMuscleLists lists: [[String]]) -> (hit: Set<BodyPart>, missing: [BodyPart]) {
        var hit = Set<BodyPart>()
        for ids in lists { hit.formUnion(parts(forMuscleIDs: ids)) }
        let missing = allCases.filter { !hit.contains($0) }
        return (hit, missing)
    }
}
