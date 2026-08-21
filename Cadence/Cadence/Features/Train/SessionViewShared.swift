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
    /// What each roster member's next set on this exercise should be. Changing
    /// "Who did this set?" re-targets the editor to that person's own plan (or
    /// their usual load and reps) instead of leaving the previous performer's
    /// numbers in place (field test 2026-08-19 #2).
    var performerDefaults: [PerformerDefault] = []
    var exerciseName: String = ""
    var setNumberText: String = ""
    var recordedText: String?
    var effortMode: WatchEffortMode = .rpe

    static func == (lhs: InlineEditorConfig, rhs: InlineEditorConfig) -> Bool {
        lhs.id == rhs.id
    }

    /// One performer's resolved next set. `weight` is already formatted in the
    /// display unit; `weightKg` is the canonical value behind it.
    struct PerformerDefault: Equatable, Identifiable {
        var id: String { performerID?.uuidString ?? "owner" }
        var performerID: UUID?
        var reps: Int
        var weightKg: Double?
        var weight: String
        /// Prior-session sets on this movement for THIS performer, already
        /// formatted (`185 lb × 5, 190 lb × 6`); nil when they have never done it
        /// (field test 2026-08-20 issue 3).
        var lastTimeText: String? = nil
        /// "Last set … · RPE n" for THIS performer's most recent working set this
        /// session; nil on their first set of the movement (field test 2026-08-20
        /// issue 3).
        var lastSetThisSession: String? = nil
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
