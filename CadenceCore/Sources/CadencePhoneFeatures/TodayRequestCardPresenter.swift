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
            return TodayRequestCardDisplay(title: title, buttonLabel: {
                #if os(Linux)
                "Suggesting…"
                #else
                String(localized: "Suggesting…", bundle: FeatureLocalization.bundle)
                #endif
            }(),
                                           isLoading: true, isTappable: false,
                                           accessibilityLabel: {
                                               #if os(Linux)
                                               "\(title), loading"
                                               #else
                                               String(localized: "\(title), loading", bundle: FeatureLocalization.bundle)
                                               #endif
                                           }())
        case .result:
            let shown = (resultSummary?.isEmpty == false ? resultSummary : nil) ?? title
            return TodayRequestCardDisplay(title: shown, buttonLabel: {
                #if os(Linux)
                "View"
                #else
                String(localized: "View", bundle: FeatureLocalization.bundle)
                #endif
            }(),
                                           isLoading: false, isTappable: true,
                                           accessibilityLabel: shown)
        case .failed(let message):
            return TodayRequestCardDisplay(title: title, buttonLabel: {
                #if os(Linux)
                "Try again"
                #else
                String(localized: "Try again", bundle: FeatureLocalization.bundle)
                #endif
            }(),
                                           isLoading: false, isTappable: true,
                                           accessibilityLabel: {
                                               #if os(Linux)
                                               "\(title) failed: \(message)"
                                               #else
                                               String(localized: "\(title) failed: \(message)", bundle: FeatureLocalization.bundle)
                                               #endif
                                           }())
        }
    }
}
