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
