import Foundation

/// The source a cardio/interval/strength start will use for live heart rate.
/// The view maps this to its app-target `HRSourceChoice`.
public enum PreWorkoutHRContinue: Equatable, Sendable {
    case watch
    case bluetooth
    case none
}

/// Everything the HR gate needs to decide about the Continue/Check buttons,
/// captured as a pure value so the decision is headless-testable (field test
/// 2026-08-20 issue 6).
public struct PreWorkoutHRState: Equatable, Sendable {
    public var watchBPM: Int?
    public var strapConnected: Bool
    /// Whether "Check for Live HR" has been tapped.
    public var watchRequested: Bool
    /// The watch relay is mid-connection (`.connecting` / `.waitingForSample`).
    public var relayBusy: Bool

    public init(watchBPM: Int?,
                strapConnected: Bool,
                watchRequested: Bool,
                relayBusy: Bool) {
        self.watchBPM = watchBPM
        self.strapConnected = strapConnected
        self.watchRequested = watchRequested
        self.relayBusy = relayBusy
    }
}

/// The HR gate's Continue/Check button decisions. NFR-8: the escape hatch must
/// never be disabled by a failed or transient sensor connection, so the primary
/// action is always available and "Check for Live HR" never blocks on transient
/// relay states — a tap during a stuck relay is exactly the recovery action the
/// user wants to take.
public enum PreWorkoutHRPresenter {

    public static func continueLabel(_ s: PreWorkoutHRState) -> String {
        if s.watchBPM != nil { return "Continue with Apple Watch" }
        if s.strapConnected { return "Continue with Bluetooth" }
        return "Continue without heart rate"
    }

    /// ALWAYS true — the fix. `continueAction` resolves the source for the live
    /// state, and the view stops a pending watch session before continuing
    /// without HR.
    public static func continueEnabled(_ s: PreWorkoutHRState) -> Bool {
        true
    }

    public static func continueAction(_ s: PreWorkoutHRState) -> PreWorkoutHRContinue {
        if s.watchBPM != nil { return .watch }
        if s.strapConnected { return .bluetooth }
        return .none
    }

    /// ALWAYS true — never blocks on `.connecting` / `.waitingForSample`. Each
    /// tap begins a fresh `start_workout` with a new requestID; the existing 15 s
    /// timeout and P5B's `.alreadyActive` recovery keep it honest.
    public static func checkEnabled(_ s: PreWorkoutHRState) -> Bool {
        true
    }
}
