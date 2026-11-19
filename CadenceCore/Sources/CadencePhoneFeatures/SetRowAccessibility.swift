import CadenceFeatures
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
            case .log: return {
                #if os(Linux)
                "Log set"
                #else
                String(localized: "Log set", bundle: FeatureLocalization.bundle)
                #endif
            }()
            case .edit: return {
                #if os(Linux)
                "Edit set"
                #else
                String(localized: "Edit set", bundle: FeatureLocalization.bundle)
                #endif
            }()
            case .repeatSet: return {
                #if os(Linux)
                "Repeat set"
                #else
                String(localized: "Repeat set", bundle: FeatureLocalization.bundle)
                #endif
            }()
            case .delete: return {
                #if os(Linux)
                "Delete set"
                #else
                String(localized: "Delete set", bundle: FeatureLocalization.bundle)
                #endif
            }()
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
            hint: {
                #if os(Linux)
                "Swipe up or use the actions menu to edit, repeat, or delete this set."
                #else
                String(localized: "Swipe up or use the actions menu to edit, repeat, or delete this set.", bundle: FeatureLocalization.bundle)
                #endif
            }(),
            actions: [.edit, .repeatSet, .delete])
    }

    public static func pending(exercise: String, setNumber: Int, planned: Int,
                               reps: Int, weight: String?, performer: String?,
                               isCurrent: Bool) -> Descriptor {
        let performerText = performer.map { ", \($0)" } ?? ""
        let weightText = weight.map { ", \($0)" } ?? ""
        let state = isCurrent ? "next set, not logged" : "not logged"
        return Descriptor(
            label: {
                #if os(Linux)
                "Set \(setNumber) of \(max(setNumber, planned)), \(exercise)\(performerText)\(weightText), \(reps) reps, \(state)"
                #else
                String(localized: "Set \(setNumber) of \(max(setNumber, planned)), \(exercise)\(performerText)\(weightText), \(reps) reps, \(state)", bundle: FeatureLocalization.bundle)
                #endif
            }(),
            hint: isCurrent ? {
                #if os(Linux)
                "Double tap to edit, or use Log set to save the next set."
                #else
                String(localized: "Double tap to edit, or use Log set to save the next set.", bundle: FeatureLocalization.bundle)
                #endif
            }() : {
                #if os(Linux)
                "Double tap to edit this planned set."
                #else
                String(localized: "Double tap to edit this planned set.", bundle: FeatureLocalization.bundle)
                #endif
            }(),
            actions: isCurrent ? [.log, .edit] : [.edit])
    }
}
