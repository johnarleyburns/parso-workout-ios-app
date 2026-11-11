import Foundation

/// The two intents the shared Cardio picker serves.
public enum CardioPickerMode: Equatable, Hashable, Sendable {
    case start
    case schedule
}

/// One top-level block of the Cardio picker, in render order.
public enum CardioPickerSection: Equatable, Hashable, Sendable {
    /// Determinate ring + "m of n min credit" (start mode only).
    case weeklyCredit
    /// The standalone Suggest Cardio action (start mode only).
    case suggestCardio
    /// "Never suggested" exclusions; renders nothing when there are none.
    case excludedTypesNoteWhenPresent
    /// The visible "Cardio" heading for the type grid (start mode only).
    case cardioSection
    case typeGrid
    /// Show more/less, including the expanded grid it discloses.
    case showMore
}

/// Value-only layout policy for `CardioPickerView` (issue #619). The view
/// renders exactly this order, so tests pin what the user sees.
public enum CardioPickerLayoutPresenter {
    public static func sections(for mode: CardioPickerMode,
                                showsWeeklyCredit: Bool,
                                showsSuggestCardio: Bool) -> [CardioPickerSection] {
        switch mode {
        case .schedule:
            // Scheduling keeps its existing grid-and-Show-more surface.
            return [.typeGrid, .showMore]
        case .start:
            var sections: [CardioPickerSection] = []
            if showsWeeklyCredit { sections.append(.weeklyCredit) }
            if showsSuggestCardio {
                sections.append(.suggestCardio)
                sections.append(.excludedTypesNoteWhenPresent)
            }
            sections += [.cardioSection, .typeGrid, .showMore]
            return sections
        }
    }
}
