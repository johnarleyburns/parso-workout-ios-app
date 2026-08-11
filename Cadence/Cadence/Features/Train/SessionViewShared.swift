import SwiftUI
import CadenceCore

// MARK: - Shared types for the inline set editor

struct SetDraft {
    var weightString: String
    var unit: MeasurementUnitPreference
    var reps: Int
    var rpe: Int?
    var bodyweight: Bool
    var performerID: UUID?
}

struct InlineEditorConfig: Equatable {
    var id = UUID()
    var isEditing: Bool
    var weight: String
    var reps: Int
    var rpe: Int?
    var bodyweight: Bool
    var performerID: UUID?
    var roster: [RosterEntry]
    var hasPartners: Bool
    var unit: MeasurementUnitPreference
    var priorWeightHint: Double?

    static func == (lhs: InlineEditorConfig, rhs: InlineEditorConfig) -> Bool {
        lhs.id == rhs.id
    }
}

struct RosterEntry: Equatable, Identifiable {
    var id: UUID? { personID }
    var personID: UUID?
    var name: String
    var isMe: Bool
}

// MARK: - Column widths (shared)

enum SetCol {
    static let num: CGFloat = 26
    static let reps: CGFloat = 64
    static let rpe: CGFloat = 26
    static let check: CGFloat = 34
    static let gap: CGFloat = 7
}
