import CadenceFeatures
import Foundation

/// Pure state for one of Today's two explicit coach-request cards (strength,
/// cardio). No automatic transitions: every state change is the direct
/// result of a tap or a request's completion, never a timer or a `.task`.
public enum TodayRequestCardState: Equatable, Sendable {
    case idle
    case requesting
    /// Collapsed: tapping reopens the full review sheet; the card itself only
    /// ever shows a short summary.
    case result
    case failed(String)
}

public struct TodayRequestCardDisplay: Equatable, Sendable {
    public let title: String
    public let buttonLabel: String
    public let isLoading: Bool
    public let isTappable: Bool
    public let accessibilityLabel: String
}

public enum TodayRequestCardPresenter {
    public static func make(title: String, state: TodayRequestCardState,
                            resultSummary: String?) -> TodayRequestCardDisplay {
        switch state {
        case .idle:
            return TodayRequestCardDisplay(title: title, buttonLabel: title,
                                           isLoading: false, isTappable: true,
                                           accessibilityLabel: title)
        case .requesting:
            return TodayRequestCardDisplay(title: title, buttonLabel: String(localized: "Suggesting…", bundle: FeatureLocalization.bundle),
                                           isLoading: true, isTappable: false,
                                           accessibilityLabel: String(localized: "\(title), loading", bundle: FeatureLocalization.bundle))
        case .result:
            let shown = (resultSummary?.isEmpty == false ? resultSummary : nil) ?? title
            return TodayRequestCardDisplay(title: shown, buttonLabel: String(localized: "View", bundle: FeatureLocalization.bundle),
                                           isLoading: false, isTappable: true,
                                           accessibilityLabel: shown)
        case .failed(let message):
            return TodayRequestCardDisplay(title: title, buttonLabel: String(localized: "Try again", bundle: FeatureLocalization.bundle),
                                           isLoading: false, isTappable: true,
                                           accessibilityLabel: String(localized: "\(title) failed: \(message)", bundle: FeatureLocalization.bundle))
        }
    }
}
