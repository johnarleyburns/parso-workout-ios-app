import Foundation

/// Describes what the currently shipped runners can safely execute from a
/// unified plan session. A session may contain any valid item families even
/// when a runner cannot yet execute that combination.
public enum PlanExecutionBoundary: Equatable, Sendable {
    public enum Modality: String, CaseIterable, Equatable, Hashable, Sendable {
        case strength
        case cardio
        case mobility
        case instruction
    }

    case empty
    case strengthOnly
    case cardioOnly
    case mobilityOnly
    case instructionOnly
    case mixed([Modality])

    public init(session: Session) {
        var modalities: [Modality] = []
        for item in session.orderedItems {
            let modality: Modality
            switch item {
            case .strength: modality = .strength
            case .cardio: modality = .cardio
            case .mobility: modality = .mobility
            case .instruction: modality = .instruction
            }
            if !modalities.contains(modality) {
                modalities.append(modality)
            }
        }

        switch modalities {
        case []: self = .empty
        case [.strength]: self = .strengthOnly
        case [.cardio]: self = .cardioOnly
        case [.mobility]: self = .mobilityOnly
        case [.instruction]: self = .instructionOnly
        default: self = .mixed(modalities)
        }
    }

    /// The existing iPhone live runner materializes only strength sessions.
    public var canStartStrengthRunner: Bool { self == .strengthOnly }

    /// The combined runner can sequence cardio and mobility items. It does not
    /// accept strength, instruction-only, or any other mixed session until a
    /// runner with those semantics exists.
    public var canStartCombinedRunner: Bool {
        switch self {
        case .cardioOnly, .mobilityOnly:
            return true
        case let .mixed(modalities):
            return Set(modalities) == Set([.cardio, .mobility])
        case .empty, .strengthOnly, .instructionOnly:
            return false
        }
    }

    /// The existing Watch launcher can execute one strength or one cardio
    /// session. It cannot safely represent a mixed session or mobility yet.
    public var canProjectToWatch: Bool {
        self == .strengthOnly || self == .cardioOnly
    }

    public var userFacingDescription: String {
        switch self {
        case .empty:
            return String(localized: "Add an item before starting this session.", bundle: .module)
        case .strengthOnly:
            return String(localized: "Starting now opens the strength runner.", bundle: .module)
        case .cardioOnly:
            return String(localized: "Cardio plans sync to Watch for the planned cardio runner.", bundle: .module)
        case .mobilityOnly:
            return String(localized: "Starting now opens the cardio and mobility runner.", bundle: .module)
        case .instructionOnly:
            return String(localized: "Instructions are saved as a plan note and are not executable yet.", bundle: .module)
        case let .mixed(modalities):
            let names = modalities.map { $0.rawValue }.joined(separator: ", ")
            if canStartCombinedRunner {
                return String(localized: "Starting now opens the cardio and mobility runner.", bundle: .module)
            }
            return String(localized: "Mixed \(names) sessions are saved; a combined runner is coming next.", bundle: .module)
        }
    }
}

public extension Session {
    var executionBoundary: PlanExecutionBoundary {
        PlanExecutionBoundary(session: self)
    }
}
