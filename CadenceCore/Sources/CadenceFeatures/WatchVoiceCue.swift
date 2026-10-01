import Foundation

/// The short, deterministic phrases spoken by the Watch workout coach. Keeping
/// phrase selection in CadenceFeatures makes the Watch presentation testable
/// without requiring AVSpeechSynthesizer or a physical Watch.
public enum WatchVoiceCue: Equatable, Sendable {
    case workoutStarted(title: String)
    case paused
    case resumed
    case phase(kind: String, round: Int?)
    case warning(seconds: Int?)
    case restComplete
    case workoutComplete

    public var speechText: String {
        switch self {
        case .workoutStarted(let title):
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Workout started" : "Workout started. (trimmed)"
        case .paused:
            return "Workout paused"
        case .resumed:
            return "Workout resumed"
        case .phase(let kind, let round):
            if kind == "work", let round { return "Round \(round)" }
            switch kind {
            case "work": return "Work"
            case "rest": return "Rest"
            case "warmup": return "Warm-up"
            case "cooldown": return "Cool-down"
            default: return kind
            }
        case .warning(let seconds):
            if let seconds { return "\(seconds) seconds" }
            return "Get ready"
        case .restComplete:
            return "Rest complete"
        case .workoutComplete:
            return "Workout complete"
        }
    }

    public var eventID: String {
        switch self {
        case .workoutStarted: return "workoutStarted"
        case .paused: return "paused"
        case .resumed: return "resumed"
        case .phase(let kind, let round): return "phase:\(kind):\(round.map(String.init) ?? "")"
        case .warning(let seconds): return "warning:\(seconds.map(String.init) ?? "")"
        case .restComplete: return "restComplete"
        case .workoutComplete: return "workoutComplete"
        }
    }
}
