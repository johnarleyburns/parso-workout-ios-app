import Foundation

/// Resolves the entities in a parsed command without mutating a workout.
/// Keeping this boundary named makes the voice pipeline auditable and gives the
/// phone and Watch a shared, headless contract.
public struct VoiceEntityResolver: Sendable {
    public init() {}

    public func resolve(_ parsed: VoiceParseResult,
                        currentExercise: String?,
                        exercises: [String],
                        performers: [String],
                        activePerformer: String? = nil) -> VoiceResolutionResult {
        VoiceCommandResolver.resolve(parsed, currentExercise: currentExercise,
                                     exercises: exercises, performers: performers,
                                     activePerformer: activePerformer)
    }
}

/// The executor deliberately only auto-executes an unambiguous set log. All
/// other commands remain reviewable, so a transcription error cannot pause,
/// finish, delete, or otherwise mutate a workout silently.
public struct VoiceCommandExecutor: Sendable {
    public init() {}

    public func automaticAction(parsed: VoiceParseResult,
                                resolution: VoiceResolutionResult) -> VoiceResolvedAction? {
        guard parsed.confidence == .exact, parsed.unsupportedTerms.isEmpty,
              case .logSet? = resolution.action else { return nil }
        return resolution.action
    }
}

public struct HeardVoiceEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let heardAt: Date
    public let transcript: String
    public let confidence: VoiceConfidence
    public let appliedAutomatically: Bool

    public init(id: UUID = UUID(), heardAt: Date = Date(), transcript: String,
                confidence: VoiceConfidence, appliedAutomatically: Bool) {
        self.id = id
        self.heardAt = heardAt
        self.transcript = transcript
        self.confidence = confidence
        self.appliedAutomatically = appliedAutomatically
    }
}

/// A bounded, user-local diagnostic log of what Quick Talk heard. It stores no
/// audio and is intentionally opt-in to persistence at the app boundary.
public struct HeardVoiceLog: Codable, Equatable, Sendable {
    public private(set) var entries: [HeardVoiceEntry]
    public let capacity: Int

    public init(entries: [HeardVoiceEntry] = [], capacity: Int = 50) {
        self.capacity = max(1, capacity)
        self.entries = Array(entries.suffix(self.capacity))
    }

    public mutating func append(_ entry: HeardVoiceEntry) {
        entries.append(entry)
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }
}

public struct QuickTalkFollowUpWindow: Equatable, Sendable {
    public static let duration: TimeInterval = 8
    public let startedAt: Date

    public init(startedAt: Date) { self.startedAt = startedAt }

    public var expiresAt: Date { startedAt.addingTimeInterval(Self.duration) }
    public func accepts(_ date: Date) -> Bool { date <= expiresAt }
}
