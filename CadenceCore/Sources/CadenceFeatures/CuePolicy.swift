import Foundation

/// The small, stable vocabulary used by the workout surfaces. Keeping the
/// policy in the feature layer makes haptic/audio decisions testable without
/// importing UIKit or running a device.
public enum CueKind: String, Codable, CaseIterable, Sendable {
    case setLogged
    case personalBest
    case restEnding
    case restDone
    case intervalWork
    case intervalRest
    case dayClosed
    case undo
}
public enum CelebrationStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case full
    case quiet
    case off

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .full: return "Full"
        case .quiet: return "Quiet (haptics only)"
        case .off: return "Off"
        }
    }
}

public struct CuePolicy: Equatable, Sendable {
    public let celebrationStyle: CelebrationStyle

    public init(celebrationStyle: CelebrationStyle = .full) {
        self.celebrationStyle = celebrationStyle
    }

    public func cue(for event: CueEvent) -> CueKind? {
        switch event {
        case .loggedSet(let isPersonalBest):
            if isPersonalBest { return celebrationStyle == .off ? nil : .personalBest }
            return celebrationStyle == .off ? nil : .setLogged
        case .rest(secondsRemaining: let seconds):
            return seconds <= 3 ? .restEnding : nil
        case .restFinished: return .restDone
        case .intervalWork: return .intervalWork
        case .intervalRest: return .intervalRest
        case .dayCompleted: return celebrationStyle == .off ? nil : .dayClosed
        case .undone: return celebrationStyle == .off ? nil : .undo
        }
    }
}

public enum CueEvent: Equatable, Sendable {
    case loggedSet(isPersonalBest: Bool)
    case rest(secondsRemaining: Int)
    case restFinished
    case intervalWork
    case intervalRest
    case dayCompleted
    case undone
}
