import SwiftUI
import CadenceCore
import CadenceFeatures

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
    var exerciseName: String = ""
    var setNumberText: String = ""
    var contextText: String?
    var recordedText: String?
    var effortMode: WatchEffortMode = .rpe

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

enum SetEditorRoute: Identifiable, Equatable {
    case add(exerciseID: UUID)
    case edit(exerciseID: UUID, setID: UUID)
    var id: String {
        switch self { case .add(let exerciseID): return "add-\(exerciseID)"; case .edit(let exerciseID, let setID): return "edit-\(exerciseID)-\(setID)" }
    }
}

// MARK: - Column widths (shared)

enum SetCol {
    static let num: CGFloat = 20
    static let reps: CGFloat = 56
    static let rpe: CGFloat = 42
    static let check: CGFloat = 34
    static let gap: CGFloat = 5
}
