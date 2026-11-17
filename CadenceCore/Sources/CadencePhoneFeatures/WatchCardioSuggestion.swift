import CadenceFeatures
import Foundation
import CadenceCore
import CadenceWorkoutFeatures

/// Transport envelope carrying a phone-generated `CardioSuggestion` to the Watch.
/// Cardio twin of `WatchCoachSuggestionEnvelope`.
public struct WatchCardioSuggestionEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumLifetime: TimeInterval = 26 * 3600

    public let schemaVersion: Int
    public let suggestion: CardioSuggestion
    public let issuedAt: Date
    public let expiresAt: Date

    public init(suggestion: CardioSuggestion, issuedAt: Date, expiresAt: Date) {
        self.schemaVersion = Self.currentSchemaVersion
        self.suggestion = suggestion
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    public static func make(suggestion: CardioSuggestion, issuedAt: Date,
                            calendar: Calendar = .current) -> WatchCardioSuggestionEnvelope {
        let start = calendar.startOfDay(for: issuedAt)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? issuedAt.addingTimeInterval(24 * 3600)
        return WatchCardioSuggestionEnvelope(suggestion: suggestion, issuedAt: issuedAt, expiresAt: next)
    }

    public var hasValidDates: Bool {
        expiresAt > issuedAt && expiresAt.timeIntervalSince(issuedAt) <= Self.maximumLifetime
    }

    public func isStartable(now: Date) -> Bool {
        hasValidDates && now < expiresAt
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public enum DecodeFailure: Error, Equatable, Sendable { case corrupt, unsupportedSchema(Int) }

    public static func decode(_ data: Data) -> Result<WatchCardioSuggestionEnvelope, DecodeFailure> {
        struct Header: Decodable { let schemaVersion: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { return .failure(.corrupt) }
        guard header.schemaVersion == currentSchemaVersion else {
            return .failure(.unsupportedSchema(header.schemaVersion))
        }
        guard let envelope = try? JSONDecoder().decode(WatchCardioSuggestionEnvelope.self, from: data),
              envelope.hasValidDates else { return .failure(.corrupt) }
        return .success(envelope)
    }
}

extension WatchSync {
    public static func contextDict(_ envelope: WatchCardioSuggestionEnvelope) throws -> [String: Any] {
        [Key.cardioSuggestionSnapshot: try envelope.encoded(),
         Key.cardioSuggestionSnapshotUpdatedAt: envelope.issuedAt]
    }
}

/// Decoded cardio payload of an incoming context.
public enum WatchCardioSuggestionPayload: Equatable, Sendable {
    /// No key in the context: an explicit removal.
    case absent
    case envelope(WatchCardioSuggestionEnvelope)
    /// Present but malformed/unsupported; must never replace a good snapshot.
    case invalid

    public init(context: [String: Any]) {
        guard let raw = context[WatchSync.Key.cardioSuggestionSnapshot] else { self = .absent; return }
        guard let data = raw as? Data, case .success(let envelope) = WatchCardioSuggestionEnvelope.decode(data) else {
            self = .invalid
            return
        }
        self = .envelope(envelope)
    }
}

public enum WatchCardioSuggestAvailability: Equatable, Sendable {
    case ready(CardioSuggestion, heading: String, syncedAt: Date)
    case needsSync(reason: Reason, lastSyncedAt: Date?)

    public enum Reason: Equatable, Sendable {
        case noSnapshot, expired
        public var message: String {
            switch self {
            case .noSnapshot: "No personalized cardio workout is on this Watch yet. A recent iPhone sync is needed."
            case .expired: "Today's personalized cardio workout needs refresh."
            }
        }
    }
}

public enum WatchCardioSuggestResolver {
    public static let readyHeading = "Synced from iPhone"

    public static func resolve(envelope: WatchCardioSuggestionEnvelope?, now: Date) -> WatchCardioSuggestAvailability {
        guard let envelope else { return .needsSync(reason: .noSnapshot, lastSyncedAt: nil) }
        guard envelope.schemaVersion == WatchCardioSuggestionEnvelope.currentSchemaVersion,
              envelope.isStartable(now: now) else {
            return .needsSync(reason: .expired, lastSyncedAt: envelope.issuedAt)
        }
        return .ready(envelope.suggestion, heading: readyHeading, syncedAt: envelope.issuedAt)
    }
}

/// Memoizes resolution the same way `WatchSuggestResolutionCache` does for strength.
public final class WatchCardioSuggestResolutionCache {
    private struct Key: Equatable { var issuedAt: Date? }
    private var key: Key?
    private var value: WatchCardioSuggestAvailability?

    public init() {}

    public func resolve(envelope: WatchCardioSuggestionEnvelope?, now: Date) -> WatchCardioSuggestAvailability {
        let k = Key(issuedAt: envelope?.issuedAt)
        if let value, key == k, envelope.map({ $0.isStartable(now: now) }) ?? true { return value }
        let result = WatchCardioSuggestResolver.resolve(envelope: envelope, now: now)
        key = k
        value = result
        return result
    }
}
