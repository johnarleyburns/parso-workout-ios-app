import Foundation

/// The safe boundary between speech parsing and workout mutation. Parsing may
/// understand a phrase, but it must not guess which catalog row or partner the
/// user meant. This resolver only returns an executable action after the phrase
/// has been matched against the current session's exercises and roster.
public enum VoiceResolutionIssue: Equatable, Sendable {
    case missingExercise
    case unknownExercise(String)
    case ambiguousExercise([String])
    case unknownPerformer(String)
    case ambiguousPerformer([String])
    case missingReps
    case missingWeight
}

public struct VoiceResolvedExercise: Equatable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

public struct VoiceResolvedPerformer: Equatable, Sendable {
    /// `nil` means the device owner (“Me”).
    public let name: String
    public let isOwner: Bool

    public init(name: String, isOwner: Bool) {
        self.name = name
        self.isOwner = isOwner
    }
}

public enum VoiceResolvedAction: Equatable, Sendable {
    case logSet(exercise: VoiceResolvedExercise, weightKg: Double?, reps: Int,
                rpe: Double?, isWarmup: Bool, performer: VoiceResolvedPerformer)
    case repeatLastSet(exercise: VoiceResolvedExercise, performer: VoiceResolvedPerformer,
                       adjustKg: Double?)
    case adjustNext(exercise: VoiceResolvedExercise, deltaKg: Double)
    case addExercise(String)
    case switchExercise(String)
    case setPerformer(VoiceResolvedPerformer)
    case addPartner(String)
    case rest(seconds: Int?)
    case skipRest
    case pause
    case resume
    case undo
    case startWorkout(String?)
    case finishWorkout
}

public struct VoiceResolutionResult: Equatable, Sendable {
    public let action: VoiceResolvedAction?
    public let issue: VoiceResolutionIssue?
    public let clarification: String?

    public init(action: VoiceResolvedAction? = nil,
                issue: VoiceResolutionIssue? = nil,
                clarification: String? = nil) {
        self.action = action
        self.issue = issue
        self.clarification = clarification
    }
}

public enum VoiceCommandResolver {
    public static func resolve(_ parsed: VoiceParseResult,
                               currentExercise: String?,
                               exercises: [String],
                               performers: [String],
                               activePerformer: String? = nil) -> VoiceResolutionResult {
        guard let command = parsed.command else {
            return VoiceResolutionResult(clarification: parsed.clarification ?? "Please try that again.")
        }

        switch command {
        case .logSet(let spec):
            guard let exercise = resolveExercise(spec.exercise?.name ?? currentExercise,
                                                 from: exercises) else {
                return unresolvedExercise(spec.exercise?.name)
            }
            guard let reps = spec.reps else {
                return VoiceResolutionResult(issue: .missingReps,
                                             clarification: "How many reps should I log?")
            }
            if !spec.isWarmup, spec.weightKg == nil,
               !exerciseLooksBodyweight(exercise) {
                return VoiceResolutionResult(issue: .missingWeight,
                                             clarification: "What weight did you use?")
            }
            let performer = resolvePerformer(spec.performer?.name ?? activePerformer,
                                             from: performers)
            guard let performer else { return unresolvedPerformer(spec.performer?.name ?? activePerformer) }
            return VoiceResolutionResult(action: .logSet(
                exercise: VoiceResolvedExercise(name: exercise), weightKg: spec.weightKg,
                reps: reps, rpe: spec.rpe, isWarmup: spec.isWarmup, performer: performer))

        case .repeatLastSet(let requestedPerformer, let adjust):
            guard let exercise = resolveExercise(currentExercise, from: exercises) else {
                return unresolvedExercise(nil)
            }
            let performer = resolvePerformer(requestedPerformer?.name ?? activePerformer,
                                             from: performers)
            guard let performer else { return unresolvedPerformer(requestedPerformer?.name) }
            return VoiceResolutionResult(action: .repeatLastSet(
                exercise: VoiceResolvedExercise(name: exercise), performer: performer,
                adjustKg: adjust?.deltaKg))

        case .adjustNext(let adjust):
            guard let exercise = resolveExercise(currentExercise, from: exercises) else {
                return unresolvedExercise(nil)
            }
            return VoiceResolutionResult(action: .adjustNext(
                exercise: VoiceResolvedExercise(name: exercise), deltaKg: adjust.deltaKg))

        case .addExercise(let ref): return VoiceResolutionResult(action: .addExercise(ref.name))
        case .switchExercise(let ref): return VoiceResolutionResult(action: .switchExercise(ref.name))
        case .setPerformer(let ref):
            guard let performer = resolvePerformer(ref.name, from: performers) else {
                return unresolvedPerformer(ref.name)
            }
            return VoiceResolutionResult(action: .setPerformer(performer))
        case .addPartner(let ref): return VoiceResolutionResult(action: .addPartner(ref.name))
        case .rest(let seconds): return VoiceResolutionResult(action: .rest(seconds: seconds))
        case .skipRest: return VoiceResolutionResult(action: .skipRest)
        case .pause: return VoiceResolutionResult(action: .pause)
        case .resume: return VoiceResolutionResult(action: .resume)
        case .undo: return VoiceResolutionResult(action: .undo)
        case .startWorkout(let ref): return VoiceResolutionResult(action: .startWorkout(ref?.name))
        case .finishWorkout: return VoiceResolutionResult(action: .finishWorkout)
        }
    }

    private static func resolveExercise(_ requested: String?, from names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        guard let requested = requested?.normalizedVoiceTerm, !requested.isEmpty else { return nil }
        let exact = names.first { $0.normalizedVoiceTerm == requested }
        if let exact { return exact }
        let matches = names.filter {
            $0.normalizedVoiceTerm.hasPrefix(requested) || requested.hasPrefix($0.normalizedVoiceTerm)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func resolvePerformer(_ requested: String?, from names: [String]) -> VoiceResolvedPerformer? {
        let ownerName = names.first(where: { $0.normalizedVoiceTerm == "me" }) ?? "Me"
        guard let requested = requested?.normalizedVoiceTerm, !requested.isEmpty else {
            return VoiceResolvedPerformer(name: ownerName, isOwner: true)
        }
        if requested == "me" || requested == "myself" || requested == "i" {
            return VoiceResolvedPerformer(name: ownerName, isOwner: true)
        }
        let matches = names.filter {
            let normalized = $0.normalizedVoiceTerm
            return normalized == requested || normalized.hasPrefix(requested) || requested.hasPrefix(normalized)
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        return VoiceResolvedPerformer(name: match, isOwner: match.normalizedVoiceTerm == "me")
    }

    private static func unresolvedExercise(_ requested: String?) -> VoiceResolutionResult {
        let issue: VoiceResolutionIssue = requested.map { .unknownExercise($0) } ?? .missingExercise
        return VoiceResolutionResult(issue: issue, clarification: requested == nil
                                      ? "Which exercise should I use?"
                                      : "I couldn't find that exercise in this workout.")
    }

    private static func unresolvedPerformer(_ requested: String?) -> VoiceResolutionResult {
        VoiceResolutionResult(issue: .unknownPerformer(requested ?? ""),
                              clarification: requested == nil
                              ? "Which person did that set?"
                              : "I couldn't match that person in this workout.")
    }

    private static func exerciseLooksBodyweight(_ name: String) -> Bool {
        let value = name.normalizedVoiceTerm
        return value.contains("pull up") || value.contains("push up") ||
            value.contains("pullup") || value.contains("pushup") ||
            value.contains("plank") || value.contains("dip")
    }
}

private extension String {
    var normalizedVoiceTerm: String {
        lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
