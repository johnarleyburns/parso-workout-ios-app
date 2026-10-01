import Foundation
import CadenceCore

// Watch redesign (plans/watch-redesign/2026-09-30/DESIGN.md §6, decisions D4/D12/D-W2): Quick
// Talk on the wrist. The watch records, the iPhone (or system dictation) turns speech into text,
// and *this* turns the text into an outcome with the same grammar, resolver and safety rule as the
// phone: an exact `logSet` saves immediately with Undo; everything else is reviewed.

/// Where the transcript came from — shown in words while it happens (V7).
public enum WatchQuickTalkSource: String, Equatable, Sendable {
    case iPhone
    case dictation
}

/// One reviewable command in a Check-this card (V3/V4).
public struct WatchQuickTalkItem: Equatable, Sendable, Identifiable {
    public let id: Int
    public let action: VoiceResolvedAction
    /// "Bench 100 kg × 5", "Switch to Back Squat", "Sam lifts next".
    public let title: String
    /// The part that was inferred rather than heard exactly ("“fine” → 5 reps"), if any.
    public let note: String?
}

/// What a transcript means for the workout.
public enum WatchQuickTalkOutcome: Equatable, Sendable {
    /// D4: an exact set log — apply now, offer Undo for the follow-up window.
    case apply(VoiceResolvedAction, summary: String)
    /// Anything inferred, ambiguous or not a set log — the user confirms each line.
    case review([WatchQuickTalkItem])
    /// Nothing usable was heard; show what was heard and example phrases (V5).
    case notUnderstood(clarification: String?)
}

public enum WatchQuickTalkPlanner {
    /// Hold-to-talk records at most this long (battery study 08: ask, don't listen).
    public static let maximumRecording: TimeInterval = 10

    public struct Context: Sendable {
        public let unit: MeasurementUnitPreference
        public let currentExercise: String?
        public let exercises: [String]
        public let performers: [String]
        public let activePerformer: String?

        public init(unit: MeasurementUnitPreference, currentExercise: String?, exercises: [String],
                    performers: [String], activePerformer: String?) {
            self.unit = unit
            self.currentExercise = currentExercise
            self.exercises = exercises
            self.performers = performers
            self.activePerformer = activePerformer
        }
    }

    public static func outcome(for transcript: String, context: Context) -> WatchQuickTalkOutcome {
        let clauses = splitClauses(transcript)
        guard !clauses.isEmpty else { return .notUnderstood(clarification: nil) }

        var items: [WatchQuickTalkItem] = []
        var lastClarification: String?
        for (index, clause) in clauses.enumerated() {
            let parsed = VoiceCommandParser.parse(clause, unit: context.unit)
            let resolution = VoiceEntityResolver().resolve(
                parsed, currentExercise: context.currentExercise, exercises: context.exercises,
                performers: context.performers, activePerformer: context.activePerformer)
            guard let action = resolution.action else {
                lastClarification = resolution.clarification ?? parsed.clarification
                continue
            }
            // D4: a single exact set log saves immediately; any other shape is reviewed.
            if clauses.count == 1,
               VoiceCommandExecutor().automaticAction(parsed: parsed, resolution: resolution) != nil {
                return .apply(action, summary: describe(action, unit: context.unit))
            }
            let note = parsed.confidence == .exact ? nil : inferredNote(parsed)
            items.append(WatchQuickTalkItem(id: index, action: action,
                                            title: describe(action, unit: context.unit), note: note))
        }
        return items.isEmpty ? .notUnderstood(clarification: lastClarification) : .review(items)
    }

    /// "switch to squats, Sam's turn" → two clauses. Splits on commas and "and then"/"then".
    static func splitClauses(_ transcript: String) -> [String] {
        let lowered = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return [] }
        var parts = [lowered]
        for separator in [",", ";", " and then ", " then "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func inferredNote(_ parsed: VoiceParseResult) -> String? {
        guard !parsed.unsupportedTerms.isEmpty || parsed.confidence != .exact else { return nil }
        if let unsupported = parsed.unsupportedTerms.first {
            return String(localized: "Didn't recognise “\(unsupported)”", bundle: .module)
        }
        return String(localized: "Some words were guessed", bundle: .module)
    }

    /// Human summary of a resolved action, for the saved toast and review rows.
    public static func describe(_ action: VoiceResolvedAction, unit: MeasurementUnitPreference) -> String {
        switch action {
        case let .logSet(exercise, weightKg, reps, rpe, isWarmup, performer):
            var text = exercise.name
            if let weightKg, weightKg > 0 {
                text += " " + Format.previousShort(weightKg, reps: reps, unit: unit)
            } else {
                text += " " + String(localized: "× \(reps)", bundle: .module)
            }
            if let rpe { text += " · " + String(localized: "RPE \(Int(rpe.rounded()))", bundle: .module) }
            if isWarmup { text += " · " + String(localized: "warm-up", bundle: .module) }
            if !performer.isOwner { text = String(localized: "\(performer.name): \(text)", bundle: .module) }
            return text
        case let .repeatLastSet(exercise, performer, adjustKg):
            let who = performer.isOwner ? "" : "\(performer.name): "
            if let adjustKg, adjustKg != 0 {
                let amount = Format.weightValue(abs(adjustKg), unit: unit, decimals: 1)
                return who + String(localized: "Same \(exercise.name), \(adjustKg > 0 ? "+" : "−")\(amount) \(unit.abbreviation)", bundle: .module)
            }
            return who + String(localized: "Same \(exercise.name) again", bundle: .module)
        case let .adjustNext(exercise, deltaKg):
            let amount = Format.weightValue(abs(deltaKg), unit: unit, decimals: 1)
            return String(localized: "Next \(exercise.name) \(deltaKg >= 0 ? "+" : "−")\(amount) \(unit.abbreviation)", bundle: .module)
        case .addExercise(let name): return String(localized: "Add \(name)", bundle: .module)
        case .switchExercise(let name): return String(localized: "Switch to \(name)", bundle: .module)
        case .setPerformer(let performer):
            return performer.isOwner ? String(localized: "You lift next", bundle: .module)
                                     : String(localized: "\(performer.name) lifts next", bundle: .module)
        case .addPartner(let name): return String(localized: "Add partner \(name)", bundle: .module)
        case .rest(let seconds?):
            return String(localized: "Rest \(Format.duration(TimeInterval(seconds)))", bundle: .module)
        case .rest(nil): return String(localized: "Start rest", bundle: .module)
        case .skipRest: return String(localized: "Skip rest", bundle: .module)
        case .pause: return String(localized: "Pause workout", bundle: .module)
        case .resume: return String(localized: "Resume workout", bundle: .module)
        case .undo: return String(localized: "Undo last set", bundle: .module)
        case .startWorkout(let name?): return String(localized: "Start \(name)", bundle: .module)
        case .startWorkout(nil): return String(localized: "Start workout", bundle: .module)
        case .finishWorkout: return String(localized: "Finish workout", bundle: .module)
        }
    }

    /// Four phrases for the "Didn't catch that" card, in the user's unit (V5).
    public static func examples(unit: MeasurementUnitPreference) -> [String] {
        // The unit word makes a set log exact (saved at once); without it the parser infers it.
        let weight = unit == .pounds ? "225 pounds" : "100 kilos"
        let partner = unit == .pounds ? "185 pounds" : "80 kilos"
        return [
            String(localized: "“\(weight) for 5”", bundle: .module),
            String(localized: "“same again”", bundle: .module),
            String(localized: "“Sam, \(partner) for 8”", bundle: .module),
            String(localized: "“rest two minutes”", bundle: .module)
        ]
    }
}

/// The watch's on-disk Heard log (text and confidence only — never audio). Wraps `HeardVoiceLog`.
public enum WatchHeardLogStore {
    static let key = "watch.quickTalk.heardLog"

    public static func load(_ defaults: UserDefaults = .standard) -> HeardVoiceLog {
        guard let data = defaults.data(forKey: key),
              let log = try? JSONDecoder().decode(HeardVoiceLog.self, from: data) else { return HeardVoiceLog() }
        return log
    }

    public static func append(_ entry: HeardVoiceEntry, _ defaults: UserDefaults = .standard) {
        var log = load(defaults)
        log.append(entry)
        if let data = try? JSONEncoder().encode(log) { defaults.set(data, forKey: key) }
    }

    public static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
