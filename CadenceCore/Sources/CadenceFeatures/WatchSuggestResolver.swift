import Foundation
import CadenceCore

/// Materializes a shared Coach option into a Watch launch through the same presenter and
/// bridge the phone uses. It never rederives reps or weights.
public enum CoachSuggestionWatchBridge {
    public static func launch(option: SuggestedWorkoutOption,
                              request: CoachSuggestionRequest) -> WatchLiftLaunch? {
        let plan = SuggestedWorkoutPresenter.editablePlan(
            for: option, unit: request.unit,
            warmupMinutes: request.warmupMinutes, cooldownMinutes: request.cooldownMinutes)
        guard let session = CoachWatchTodayBridge.suggestedStrengthSession(from: plan) else { return nil }
        return WatchLiftLaunch(title: session.label, exerciseNames: session.exerciseNames,
                               repLadder: session.repLadder, planPayload: session.planPayload)
    }
}

/// Watch-local facts that make a stored Coach snapshot unusable.
public struct WatchCoachHistoryState: Equatable, Sendable {
    /// Set when Watch-local strength history changed; snapshots issued at or before it are unusable.
    public var invalidatedAt: Date?
    /// Bumped on every local invalidation so memoized results are never reused across one.
    public var generation: Int

    public init(invalidatedAt: Date? = nil, generation: Int = 0) {
        self.invalidatedAt = invalidatedAt
        self.generation = generation
    }
}

public enum WatchSuggestAvailability: Equatable, Sendable {
    case ready(WatchLiftLaunch, heading: String, syncedAt: Date)
    case needsSync(reason: Reason, lastSyncedAt: Date?)

    public enum Reason: Equatable, Sendable {
        case noSnapshot, expired, historyChanged, unsupportedSnapshot, generationFailed

        public var message: String {
            switch self {
            case .noSnapshot: "No suggestion is on this Watch yet. A recent iPhone sync is needed."
            case .expired: "Today's suggestion needs refresh."
            case .historyChanged: "A workout changed since this suggestion. Refresh from iPhone."
            case .unsupportedSnapshot: "This suggestion can't be read. Update Cladiron on iPhone and sync."
            case .generationFailed: "Couldn't build today's suggestion. Sync with iPhone to try again."
            }
        }

        public var accessibilityLabel: String {
            switch self {
            case .historyChanged: "Suggestion can't be used because a workout changed. Sync with iPhone."
            default: "Suggestion needs iPhone refresh. " + message
            }
        }
    }

    public var launch: WatchLiftLaunch? {
        if case .ready(let launch, _, _) = self { return launch }
        return nil
    }
}

public enum WatchSuggestResolver {
    public static let readyHeading = "Synced from iPhone"
    public static let readyAccessibilityLabel = "Suggestion ready, same as iPhone"

    public static func resolve(envelope: WatchCoachSuggestionEnvelope?, now: Date,
                               historyState: WatchCoachHistoryState = .init(),
                               calendar: Calendar = .current) -> WatchSuggestAvailability {
        guard let envelope else {
            return .needsSync(reason: historyState.invalidatedAt == nil ? .noSnapshot : .historyChanged,
                              lastSyncedAt: nil)
        }
        let synced = envelope.issuedAt
        guard envelope.schemaVersion == WatchCoachSuggestionEnvelope.currentSchemaVersion,
              envelope.snapshot.schemaVersion == CoachSuggestionSnapshot.currentSchemaVersion,
              envelope.hasValidDates else {
            return .needsSync(reason: .unsupportedSnapshot, lastSyncedAt: synced)
        }
        if let invalidated = historyState.invalidatedAt, synced <= invalidated {
            return .needsSync(reason: .historyChanged, lastSyncedAt: synced)
        }
        guard envelope.isStartable(now: now),
              CoachSuggestionSnapshot.dayKey(for: now, calendar: calendar) == envelope.snapshot.dayKey else {
            return .needsSync(reason: .expired, lastSyncedAt: synced)
        }
        guard let option = CoachSuggestionService.generate(from: envelope.snapshot),
              let launch = CoachSuggestionWatchBridge.launch(option: option, request: envelope.snapshot.request) else {
            return .needsSync(reason: .generationFailed, lastSyncedAt: synced)
        }
        return .ready(launch, heading: readyHeading, syncedAt: synced)
    }
}

/// Memoizes resolution so SwiftUI refreshes don't re-run the solver. Keyed by snapshot
/// fingerprint, invalidation generation and local day.
public final class WatchSuggestResolutionCache {
    private struct Key: Equatable {
        var fingerprint: String?
        var issuedAt: Date?
        var generation: Int
        var dayKey: String
    }
    private var key: Key?
    private var value: WatchSuggestAvailability?
    public private(set) var generationCount = 0

    public init() {}

    public func resolve(envelope: WatchCoachSuggestionEnvelope?, now: Date,
                        historyState: WatchCoachHistoryState = .init(),
                        calendar: Calendar = .current) -> WatchSuggestAvailability {
        let k = Key(fingerprint: envelope?.sourceRevision, issuedAt: envelope?.issuedAt,
                    generation: historyState.generation,
                    dayKey: CoachSuggestionSnapshot.dayKey(for: now, calendar: calendar))
        // Expiry within a day is time-dependent; only reuse while still before expiry.
        if let value, key == k, envelope.map({ $0.isStartable(now: now) }) ?? true { return value }
        let result = WatchSuggestResolver.resolve(envelope: envelope, now: now,
                                                  historyState: historyState, calendar: calendar)
        if case .ready = result { generationCount += 1 }
        key = k
        value = result
        return result
    }
}

/// Review text derived from the launch payload only.
public struct WatchSuggestReview: Equatable, Sendable {
    public var title: String
    public var exerciseLines: [String]
    public var prescriptionDetail: String

    public init(launch: WatchLiftLaunch) {
        title = launch.title
        let strength = launch.planPayload?.strength
        if let prescriptions = strength?.prescriptions, !prescriptions.isEmpty {
            exerciseLines = prescriptions.map { p in
                let working = p.sets.filter { !$0.isWarmup }
                return "\(p.exerciseName) · \(working.count)×\(Self.repsText(working.map(\.targetReps)))"
            }
            let total = prescriptions.reduce(0) { $0 + $1.sets.filter { !$0.isWarmup }.count }
            prescriptionDetail = "\(total) working sets"
        } else {
            exerciseLines = launch.exerciseNames
            prescriptionDetail = launch.repLadder.isEmpty ? "" : "Reps " + launch.repLadder.map(String.init).joined(separator: "-")
        }
    }

    static func repsText(_ reps: [Int]) -> String {
        guard let first = reps.first else { return "0" }
        return reps.allSatisfy({ $0 == first }) ? "\(first)" : reps.map(String.init).joined(separator: "/")
    }
}
