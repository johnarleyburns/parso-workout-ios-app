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
            return {
                #if os(Linux)
                "Add an item before starting this session."
                #else
                String(localized: "Add an item before starting this session.", bundle: .module)
                #endif
            }()
        case .strengthOnly:
            return {
                #if os(Linux)
                "Starting now opens the strength runner."
                #else
                String(localized: "Starting now opens the strength runner.", bundle: .module)
                #endif
            }()
        case .cardioOnly:
            return {
                #if os(Linux)
                "Cardio plans sync to Watch for the planned cardio runner."
                #else
                String(localized: "Cardio plans sync to Watch for the planned cardio runner.", bundle: .module)
                #endif
            }()
        case .mobilityOnly:
            return {
                #if os(Linux)
                "Starting now opens the cardio and mobility runner."
                #else
                String(localized: "Starting now opens the cardio and mobility runner.", bundle: .module)
                #endif
            }()
        case .instructionOnly:
            return {
                #if os(Linux)
                "Instructions are saved as a plan note and are not executable yet."
                #else
                String(localized: "Instructions are saved as a plan note and are not executable yet.", bundle: .module)
                #endif
            }()
        case let .mixed(modalities):
            let names = modalities.map { $0.rawValue }.joined(separator: ", ")
            if canStartCombinedRunner {
                return {
                    #if os(Linux)
                    "Starting now opens the cardio and mobility runner."
                    #else
                    String(localized: "Starting now opens the cardio and mobility runner.", bundle: .module)
                    #endif
                }()
            }
            return {
                #if os(Linux)
                "Mixed \(names) sessions are saved; a combined runner is coming next."
                #else
                String(localized: "Mixed \(names) sessions are saved; a combined runner is coming next.", bundle: .module)
                #endif
            }()
        }
    }
}

public extension Session {
    var executionBoundary: PlanExecutionBoundary {
        PlanExecutionBoundary(session: self)
    }
}
