import Foundation

/// The user's primary training goal (strength-pivot decision D4). Drives the
/// engine's intensity×goal insight (see `KnowledgeBase`) and, in later phases, the
/// prescriptive recommendations. Persisted as a raw string in app settings.
public enum TrainingGoal: String, CaseIterable, Codable, Sendable, Identifiable {
    case strength
    case hypertrophy
    case endurance

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strength:    return "Strength"
        case .hypertrophy: return String(localized: "Hypertrophy", bundle: .module)
        case .endurance:   return String(localized: "Endurance", bundle: .module)
        }
    }

    /// One-line description of what the goal trains for (used in pickers/onboarding).
    public var summary: String {
        switch self {
        case .strength:    return String(localized: "Lift heavier — maximal force in low reps.", bundle: .module)
        case .hypertrophy: return String(localized: "Build muscle — moderate reps near failure.", bundle: .module)
        case .endurance:   return String(localized: "Last longer — higher reps, lighter loads.", bundle: .module)
        }
    }

    /// The working rep range the prescriptive engine programs to for this goal
    /// (P5). From the load/rep continuum (Schoenfeld et al. 2021): strength favours
    /// heavy low-rep work; hypertrophy a moderate range near failure. Endurance
    /// resolves through DB++'s `general-endurance-v1` policy, with a conservative
    /// literal retained only as a last-resort offline fallback.
    public var repRange: ClosedRange<Int> {
        switch self {
        case .strength:    return 3...5
        case .hypertrophy: return 6...12
        case .endurance:
            return TrainingEngineBridge.goalDefaults(
                policyId: "general-endurance-v1"
            )?.reps ?? 15...20
        }
    }

    /// The default reps-in-reserve the engine prescribes — how close to failure to
    /// train. Hypertrophy is driven by proximity to failure, so it sits closest;
    /// strength leaves a little more in the tank to keep bar speed and technique.
    public var targetRIR: Int {
        switch self {
        case .strength:    return 2
        case .hypertrophy: return 1
        case .endurance:
            return TrainingEngineBridge.goalDefaults(
                policyId: "general-endurance-v1"
            )?.rir ?? 2
        }
    }

    public var targetLoadPercentage: Double {
        switch self {
        case .strength:    return 0.85
        case .hypertrophy: return 0.725
        case .endurance:   return 0.575
        }
    }
}
