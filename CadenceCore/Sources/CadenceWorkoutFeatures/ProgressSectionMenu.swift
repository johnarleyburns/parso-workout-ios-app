import Foundation

/// One row of the Progress section menu: every progress question in display
/// order, with the current one marked.
public struct ProgressSectionMenuItem: Identifiable, Equatable, Sendable {
    public let question: ProgressQuestion
    public let isSelected: Bool
    public var id: String { question.rawValue }
    public var title: String { question.displayName }
    public var accessibilityIdentifier: String { "progress.question.\(question.rawValue)" }

    public init(question: ProgressQuestion, isSelected: Bool) {
        self.question = question
        self.isSelected = isSelected
    }
}

public enum ProgressSectionMenu {
    /// The horizontal chip scroller is gone; the same order now lives in the
    /// overflow menu, with exactly one selected item.
    public static func items(for selection: ProgressQuestionSelection) -> [ProgressSectionMenuItem] {
        ProgressQuestion.alphabetical.map {
            ProgressSectionMenuItem(question: $0, isSelected: $0 == selection.selected)
        }
    }
}
