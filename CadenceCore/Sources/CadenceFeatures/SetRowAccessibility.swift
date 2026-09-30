import Foundation

/// The semantic contract used by the live workout set rows.
///
/// Keeping this text in CadenceFeatures makes the VoiceOver experience testable
/// without constructing SwiftUI, and keeps partner/warm-up wording consistent
/// across the phone and Watch surfaces.
public enum SetRowAccessibility {
    public enum Action: String, CaseIterable, Sendable {
        case log
        case edit
        case repeatSet
        case delete

        public var displayName: String {
            switch self {
            case .log: return "Log set"
            case .edit: return "Edit set"
            case .repeatSet: return "Repeat set"
            case .delete: return "Delete set"
            }
        }
    }

    public struct Descriptor: Equatable, Sendable {
        public let label: String
        public let hint: String
        public let actions: [Action]

        public init(label: String, hint: String, actions: [Action]) {
            self.label = label
            self.hint = hint
            self.actions = actions
        }
    }

    public static func completed(exercise: String, setNumber: String,
                                 weight: String, reps: Int, rpe: Int?,
                                 performer: String?, isWarmup: Bool) -> Descriptor {
        let setText = isWarmup ? "warm-up set" : "set \(setNumber)"
        let performerText = performer.map { ", \($0)" } ?? ""
        let rpeText = rpe.map { ", RPE \($0)" } ?? ""
        return Descriptor(
            label: "\(setText), \(exercise)\(performerText), \(weight) × \(reps), logged\(rpeText)",
            hint: "Swipe up or use the actions menu to edit, repeat, or delete this set.",
            actions: [.edit, .repeatSet, .delete])
    }

    public static func pending(exercise: String, setNumber: Int, planned: Int,
                               reps: Int, weight: String?, performer: String?,
                               isCurrent: Bool) -> Descriptor {
        let performerText = performer.map { ", \($0)" } ?? ""
        let weightText = weight.map { ", \($0)" } ?? ""
        let state = isCurrent ? "next set, not logged" : "not logged"
        return Descriptor(
            label: "Set \(setNumber) of \(max(setNumber, planned)), \(exercise)\(performerText)\(weightText), \(reps) reps, \(state)",
            hint: isCurrent ? "Double tap to edit, or use Log set to save the next set." : "Double tap to edit this planned set.",
            actions: isCurrent ? [.log, .edit] : [.edit])
    }
}
