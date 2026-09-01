import Foundation
import FreeExerciseDBPlusPlus

/// The single boundary between Cadence domain types and the DB++ training engine.
public enum TrainingEngineBridge {
    /// Built once for deterministic, offline use. Callers retain their local defaults
    /// if the bundled database cannot be loaded on a supported device.
    public static let shared: FreeExerciseDBPlusPlus.TrainingEngine? = {
        try? FreeExerciseDBPlusPlus.TrainingEngine.bundled()
    }()

    /// Reads rep and effort defaults from a released DB++ goal policy.
    /// `useSharedEngine` exists so the fallback path can be covered without mutating
    /// process-wide state.
    static func goalDefaults(
        policyId: String,
        useSharedEngine: Bool = true
    ) -> (reps: ClosedRange<Int>, rir: Int)? {
        let engine = useSharedEngine ? shared : nil
        guard let policy = engine?.goalPolicy(policyId),
              case let .object(object) = policy,
              case let .object(reps)? = object["reps"],
              case let .number(lowerBound)? = reps["min"],
              case let .number(upperBound)? = reps["max"],
              case let .object(effort)? = object["effort"],
              case let .number(rir)? = effort["rir"]
        else { return nil }

        return (Int(lowerBound)...Int(upperBound), Int(rir))
    }
}

// MARK: - Database boundary

extension TrainingEngineBridge {
    /// App-facing snapshot of one DB++ exercise. Keeping this value type here
    /// prevents DB++'s `Exercise` and `JSONValue` types from leaking into the
    /// catalog, evidence, or persistence layers.
    struct ExerciseRecord: Equatable, Sendable {
        let exerciseId: String
        let name: String
        let force: String?
        let level: String?
        let mechanic: String?
        let equipment: String?
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let instructions: [String]
        let category: String
        let images: [String]
        let direct: [String]
        let indirect: [String]
        let stabilizers: [String]
        let patterns: [String]
        let volumeEligible: Bool
        let confidence: String?
    }

    struct EvidencePattern: Equatable, Sendable {
        let status: String
        let summary: String
        let references: [String]
    }

    struct EvidenceReference: Equatable, Sendable {
        let title: String
        let type: String
        let url: String
    }

    /// Records are sorted by the stable DB++ exercise id before crossing the
    /// boundary, so catalog seeding remains deterministic across launches.
    static var exerciseRecords: [ExerciseRecord] {
        shared?.database.allExercises.values
            .sorted { $0.exerciseId < $1.exerciseId }
            .compactMap(record(from:)) ?? []
    }

    /// Reads a scalar source field without exposing DB++'s JSON representation.
    static func sourceString(
        _ exercise: FreeExerciseDBPlusPlus.Exercise,
        _ key: String
    ) -> String? {
        guard case let .string(value)? = exercise.source?[key] else { return nil }
        return value
    }

    /// Reads a string-array source field without exposing DB++'s JSON representation.
    static func sourceStrings(
        _ exercise: FreeExerciseDBPlusPlus.Exercise,
        _ key: String
    ) -> [String] {
        guard case let .array(values)? = exercise.source?[key] else { return [] }
        return values.compactMap { value in
            guard case let .string(string) = value else { return nil }
            return string
        }
    }

    static var setCredits: (direct: Double, indirect: Double, stabilizer: Double) {
        shared?.database.setCredits ?? (direct: 1.0, indirect: 0.5, stabilizer: 0.0)
    }

    static func metadataString(_ key: String) -> String? {
        guard case let .string(value)? = shared?.database.metadata[key] else { return nil }
        return value
    }

    static func metadataInt(_ key: String) -> Int? {
        guard case let .number(value)? = shared?.database.metadata[key] else { return nil }
        return Int(value)
    }

    static var evidencePatterns: [String: EvidencePattern] {
        guard case let .object(evidence)? = shared?.database.metadata["evidence"],
              case let .object(patterns)? = evidence["patterns"]
        else { return [:] }

        return patterns.compactMapValues { value in
            guard case let .object(pattern) = value,
                  case let .string(status)? = pattern["status"],
                  case let .string(summary)? = pattern["summary"]
            else { return nil }
            return EvidencePattern(
                status: status,
                summary: summary,
                references: stringArray(pattern["references"])
            )
        }
    }

    static var evidenceReferences: [String: EvidenceReference] {
        guard case let .object(evidence)? = shared?.database.metadata["evidence"],
              case let .object(references)? = evidence["references"]
        else { return [:] }

        return references.compactMapValues { value in
            guard case let .object(reference) = value,
                  case let .string(title)? = reference["title"],
                  case let .string(type)? = reference["type"],
                  case let .string(url)? = reference["url"]
            else { return nil }
            return EvidenceReference(title: title, type: type, url: url)
        }
    }

    private static func record(
        from exercise: FreeExerciseDBPlusPlus.Exercise
    ) -> ExerciseRecord? {
        guard let name = sourceString(exercise, "name"),
              let category = sourceString(exercise, "category")
        else { return nil }

        return ExerciseRecord(
            exerciseId: exercise.exerciseId,
            name: name,
            force: sourceString(exercise, "force"),
            level: sourceString(exercise, "level"),
            mechanic: sourceString(exercise, "mechanic"),
            equipment: sourceString(exercise, "equipment"),
            primaryMuscles: sourceStrings(exercise, "primaryMuscles"),
            secondaryMuscles: sourceStrings(exercise, "secondaryMuscles"),
            instructions: sourceStrings(exercise, "instructions"),
            category: category,
            images: sourceStrings(exercise, "images"),
            direct: exercise.annotation.direct,
            indirect: exercise.annotation.indirect,
            stabilizers: exercise.annotation.stabilizers,
            patterns: exercise.annotation.patterns,
            volumeEligible: exercise.annotation.volumeEligible,
            confidence: exercise.annotation.confidence
        )
    }

    private static func stringArray(_ value: FreeExerciseDBPlusPlus.JSONValue?) -> [String] {
        guard case let .array(values)? = value else { return [] }
        return values.compactMap { element in
            guard case let .string(value) = element else { return nil }
            return value
        }
    }
}
