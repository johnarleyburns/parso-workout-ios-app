import Foundation
import CadenceCore

/// Render order and visibility for the Observations surface (Progress).
///
/// The card deliberately contains observations only. Suggested workouts are an
/// independent weekly-gap action, so their availability never depends on the
/// daily Coach decision (including rest and recovery days).
public enum ObservationsPresenter {

    /// The card's observation blocks, in render order.
    public enum Block: Equatable {
        case heading
        case suggestion(HomeSuggestion)
        case showMore(expanded: Bool)
    }

    /// Tone → a semantic colour role the view maps (no SwiftUI in this module).
    public enum ToneRole: Equatable, Sendable { case positive, warning, neutral }

    public static func toneRole(_ tone: HomeSuggestion.Tone) -> ToneRole {
        switch tone {
        case .positive: return .positive
        case .warning: return .warning
        case .neutral: return .neutral
        }
    }

    /// True when the surface shows the explicit empty state (no show-more).
    public static func isEmpty(suggestions: [HomeSuggestion]) -> Bool { suggestions.isEmpty }

    public static func blocks(suggestions: [HomeSuggestion], expanded: Bool) -> [Block] {
        var blocks: [Block] = [.heading]

        let visible = HomeDashboardPresenter.visibleSuggestions(suggestions, expanded: expanded)
        blocks.append(contentsOf: visible.map { Block.suggestion($0) })
        if suggestions.count > 1 {
            blocks.append(.showMore(expanded: expanded))
        }

        return blocks
    }

}
