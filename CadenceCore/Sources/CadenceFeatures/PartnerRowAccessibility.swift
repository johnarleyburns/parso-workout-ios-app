import Foundation

/// VoiceOver-facing semantics for one row of the plan editor's partner
/// selector. The row is a plain `Button`; the view maps `isSelected` onto the
/// `.isSelected` trait and renders the checkmark from the same flag, so the
/// state never rests on color alone.
public struct PartnerRowAccessibility: Equatable, Sendable {
    public let name: String
    public let isSelected: Bool

    public init(name: String, isSelected: Bool) {
        self.name = name
        self.isSelected = isSelected
    }

    public var label: String { name }
    public var value: String { isSelected ? "Selected" : "Not selected" }
    public var hint: String {
        isSelected ? "Double-tap to remove \(name) as a training partner"
                   : "Double-tap to add \(name) as a training partner"
    }
    /// The selected trait is applied only while selected.
    public var hasSelectedTrait: Bool { isSelected }
    public var identifier: String { "editor.partner.\(name)" }

    /// State after one activation.
    public var toggled: PartnerRowAccessibility {
        PartnerRowAccessibility(name: name, isSelected: !isSelected)
    }
}
