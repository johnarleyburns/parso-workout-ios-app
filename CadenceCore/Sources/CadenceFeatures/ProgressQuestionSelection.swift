import Foundation

/// The single progress question summarized at the top of the Progress tab.
public enum ProgressQuestion: String, CaseIterable, Sendable, Identifiable {
    case consistency
    case exerciseProgression
    case muscleVolume
    case cardioChange

    public var id: String { rawValue }
}

public struct ProgressQuestionSelection: Equatable, Sendable {
    public private(set) var selected: ProgressQuestion

    public init(selected: ProgressQuestion = .consistency) {
        self.selected = selected
    }

    public mutating func select(_ question: ProgressQuestion) {
        selected = question
    }
}
