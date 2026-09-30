import Foundation

/// The durable checkpoints for the H5 single-store → split-store migration.
/// The runner is platform-specific; this contract keeps ordering and safety
/// rules pure so a killed migration can resume without guessing what ran.
public enum StoreMigrationStep: String, Codable, CaseIterable, Hashable, Sendable {
    case preflight
    case snapshot
    case copy
    case healthBackfill
    case verify
    case switchStore
    case retainOldCopy
    case purgeOldCopy
    case complete
}

public enum StoreMigrationBlocker: Equatable, Codable, Sendable {
    case healthAccessRequired
    case snapshotRequired
    case verificationMismatch([String])
    case retentionNotElapsed(Date)
    case explicitPurgeConfirmationRequired
}

public struct StoreMigrationCounts: Codable, Equatable, Sendable {
    public var sessions: Int
    public var ownerSets: Int
    public var cardio: Int
    public var assessments: Int

    public init(sessions: Int = 0, ownerSets: Int = 0, cardio: Int = 0,
                assessments: Int = 0) {
        self.sessions = sessions
        self.ownerSets = ownerSets
        self.cardio = cardio
        self.assessments = assessments
    }
}

public struct StoreMigrationProgress: Codable, Equatable, Sendable {
    public var completed: Set<StoreMigrationStep>
    public var snapshotCreated: Bool
    public var oldCopyRetainedUntil: Date?
    public var purgeConfirmed: Bool

    public init(completed: Set<StoreMigrationStep> = [],
                snapshotCreated: Bool = false,
                oldCopyRetainedUntil: Date? = nil,
                purgeConfirmed: Bool = false) {
        self.completed = completed
        self.snapshotCreated = snapshotCreated
        self.oldCopyRetainedUntil = oldCopyRetainedUntil
        self.purgeConfirmed = purgeConfirmed
    }
}

public struct StoreMigrationFacts: Equatable, Sendable {
    public var healthWriteAuthorized: Bool
    public var autoSaveHealth: Bool
    public var oldCounts: StoreMigrationCounts
    public var newCounts: StoreMigrationCounts
    public var verificationMismatches: [String]
    public var now: Date

    public init(healthWriteAuthorized: Bool, autoSaveHealth: Bool,
                oldCounts: StoreMigrationCounts = .init(),
                newCounts: StoreMigrationCounts = .init(),
                verificationMismatches: [String] = [],
                now: Date = Date()) {
        self.healthWriteAuthorized = healthWriteAuthorized
        self.autoSaveHealth = autoSaveHealth
        self.oldCounts = oldCounts
        self.newCounts = newCounts
        self.verificationMismatches = verificationMismatches
        self.now = now
    }
}

public enum StoreMigrationDecision: Equatable, Sendable {
    case run(StoreMigrationStep)
    case blocked(StoreMigrationBlocker)
    case finished
}

public enum StoreMigrationPlanner {
    /// Returns the only safe next action. A runner should persist progress
    /// after each successful action and call this again, making retries
    /// idempotent and safe after termination.
    public static func next(progress: StoreMigrationProgress,
                            facts: StoreMigrationFacts) -> StoreMigrationDecision {
        if progress.completed.contains(.complete) { return .finished }

        if !progress.completed.contains(.preflight) {
            guard facts.healthWriteAuthorized && facts.autoSaveHealth else {
                return .blocked(.healthAccessRequired)
            }
            return .run(.preflight)
        }
        if !progress.snapshotCreated || !progress.completed.contains(.snapshot) {
            return .blocked(.snapshotRequired)
        }
        if !progress.completed.contains(.copy) { return .run(.copy) }
        if !progress.completed.contains(.healthBackfill) { return .run(.healthBackfill) }
        if !progress.completed.contains(.verify) {
            guard facts.verificationMismatches.isEmpty else {
                return .blocked(.verificationMismatch(facts.verificationMismatches))
            }
            return .run(.verify)
        }
        if !progress.completed.contains(.switchStore) { return .run(.switchStore) }
        if !progress.completed.contains(.retainOldCopy) {
            return .run(.retainOldCopy)
        }
        guard let retainedUntil = progress.oldCopyRetainedUntil else {
            // The runner sets this when it completes retainOldCopy. Returning
            // the same action is intentional: it is safe to retry after a
            // crash between copying the old store and persisting the date.
            return .run(.retainOldCopy)
        }
        guard facts.now >= retainedUntil else {
            return .blocked(.retentionNotElapsed(retainedUntil))
        }
        guard progress.purgeConfirmed else {
            return .blocked(.explicitPurgeConfirmationRequired)
        }
        if !progress.completed.contains(.purgeOldCopy) { return .run(.purgeOldCopy) }
        return .run(.complete)
    }

    /// The verification facts are deliberately derived from counts rather
    /// than trusting a runner's "success" flag. This gives the UI a stable,
    /// user-readable mismatch report before any store switch is attempted.
    public static func countMismatches(old: StoreMigrationCounts,
                                       new: StoreMigrationCounts) -> [String] {
        var mismatches: [String] = []
        if old.sessions != new.sessions { mismatches.append("sessions") }
        if old.ownerSets != new.ownerSets { mismatches.append("owner sets") }
        if old.cardio != new.cardio { mismatches.append("cardio") }
        if old.assessments != new.assessments { mismatches.append("assessments") }
        return mismatches
    }
}
