import Foundation
import CadenceCore

/// Render order and visibility for Home's Observations card.
///
/// The card deliberately contains observations only. Suggested workouts are an
/// independent weekly-gap action, so their availability never depends on the
/// daily Coach decision (including rest and recovery days).
public enum HomeCoachSectionPresenter {

    /// The card's blocks, in render order. The suggested workout is always last.
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
