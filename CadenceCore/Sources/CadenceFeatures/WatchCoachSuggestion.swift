import Foundation

/// Phone→Watch transport envelope around the exact shared `CoachSuggestionSnapshot`.
/// Transport and persistence only: the Watch evaluates it with `CoachSuggestionService`.
public struct WatchCoachSuggestionEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    /// Tolerated Watch-behind-phone clock skew before an envelope is "from the future".
    public static let futureTolerance: TimeInterval = 120
    /// A local-day boundary is at most ~25 h away (DST); anything longer is malformed.
    public static let maximumLifetime: TimeInterval = 26 * 3600

    public let schemaVersion: Int
    public let snapshot: CoachSuggestionSnapshot
    public let issuedAt: Date
    public let expiresAt: Date
    public let sourceRevision: String

    public init(snapshot: CoachSuggestionSnapshot, issuedAt: Date, expiresAt: Date, sourceRevision: String) {
        self.schemaVersion = Self.currentSchemaVersion
        self.snapshot = snapshot
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.sourceRevision = sourceRevision
    }

    /// Phone-side factory: identity is the snapshot fingerprint; expiry is the next local-day boundary.
    public static func make(snapshot: CoachSuggestionSnapshot, issuedAt: Date,
                            calendar: Calendar = .current) -> WatchCoachSuggestionEnvelope {
        let start = calendar.startOfDay(for: issuedAt)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? issuedAt.addingTimeInterval(24 * 3600)
        return WatchCoachSuggestionEnvelope(snapshot: snapshot, issuedAt: issuedAt, expiresAt: next,
                                            sourceRevision: snapshot.fingerprint)
    }

    /// Structurally sane dates; failing this is a malformed payload.
    public var hasValidDates: Bool {
        expiresAt > issuedAt && expiresAt.timeIntervalSince(issuedAt) <= Self.maximumLifetime
    }

    /// Fails closed: expired (`now >= expiresAt`), future-issued, or malformed data is not startable.
    public func isStartable(now: Date) -> Bool {
        hasValidDates && now < expiresAt && issuedAt <= now.addingTimeInterval(Self.futureTolerance)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public enum DecodeFailure: Error, Equatable, Sendable {
        case corrupt
        case unsupportedSchema(Int)
    }

    /// Strict: unknown envelope or snapshot schema versions and bad dates are rejected.
    public static func decode(_ data: Data) -> Result<WatchCoachSuggestionEnvelope, DecodeFailure> {
        struct Header: Decodable {
            struct Inner: Decodable { let schemaVersion: Int }
            let schemaVersion: Int
            let snapshot: Inner
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { return .failure(.corrupt) }
        guard header.schemaVersion == currentSchemaVersion else {
            return .failure(.unsupportedSchema(header.schemaVersion))
        }
        guard header.snapshot.schemaVersion == CoachSuggestionSnapshot.currentSchemaVersion else {
            return .failure(.unsupportedSchema(header.snapshot.schemaVersion))
        }
        guard let envelope = try? JSONDecoder().decode(WatchCoachSuggestionEnvelope.self, from: data),
              envelope.hasValidDates, !envelope.sourceRevision.isEmpty else { return .failure(.corrupt) }
        return .success(envelope)
    }
}

extension WatchSync {
    public static func contextDict(_ envelope: WatchCoachSuggestionEnvelope) throws -> [String: Any] {
        [Key.coachSuggestionSnapshot: try envelope.encoded(),
         Key.coachSuggestionSnapshotUpdatedAt: envelope.issuedAt]
    }
}

/// Decoded Coach payload of an incoming context.
public enum WatchCoachSuggestionPayload: Equatable, Sendable {
    /// No key in the context: in a handshake snapshot this is an explicit removal.
    case absent
    case envelope(WatchCoachSuggestionEnvelope)
    /// Present but malformed/unsupported; must never replace a good snapshot.
    case invalid

    public init(context: [String: Any]) {
        guard let raw = context[WatchSync.Key.coachSuggestionSnapshot] else { self = .absent; return }
        guard let data = raw as? Data, case .success(let envelope) = WatchCoachSuggestionEnvelope.decode(data) else {
            self = .invalid
            return
        }
        self = .envelope(envelope)
    }
}

/// Durable single-slot Watch storage. `UserDefaults` implementation key: `watch.coachSuggestion.envelope.v1`
/// (JSON `Data`), invalidation marker `watch.coachSuggestion.invalidatedAt.v1`.
public protocol WatchCoachSuggestionStoring: AnyObject {
    func loadData() -> Data?
    /// Atomic: on throw the previous value must be intact.
    func saveData(_ data: Data) throws
    func deleteData() throws
    func loadInvalidatedAt() -> Date?
    func saveInvalidatedAt(_ date: Date)
}

public final class UserDefaultsWatchCoachSuggestionStore: WatchCoachSuggestionStoring, @unchecked Sendable {
    public static let envelopeKey = "watch.coachSuggestion.envelope.v1"
    public static let invalidatedKey = "watch.coachSuggestion.invalidatedAt.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func loadData() -> Data? { defaults.data(forKey: Self.envelopeKey) }
    public func saveData(_ data: Data) throws { defaults.set(data, forKey: Self.envelopeKey) }
    public func deleteData() throws { defaults.removeObject(forKey: Self.envelopeKey) }
    public func loadInvalidatedAt() -> Date? { defaults.object(forKey: Self.invalidatedKey) as? Date }
    public func saveInvalidatedAt(_ date: Date) { defaults.set(date, forKey: Self.invalidatedKey) }
}

/// Pure Watch-side lifecycle rules for the persisted envelope. Not an actor; callers serialize it.
public final class WatchCoachSuggestionCoordinator {
    public enum Outcome: Equatable, Sendable {
        /// Persisted (or already current): safe to acknowledge the WC snapshot.
        case applied
        /// An older or locally-invalidated delivery was ignored; the prior state stands. Safe to acknowledge.
        case ignored
        /// Removal delivered and applied.
        case removed
        /// Malformed/unsupported, or the durable write failed: prior envelope kept; do NOT acknowledge.
        case rejected
    }

    private let store: WatchCoachSuggestionStoring
    public private(set) var current: WatchCoachSuggestionEnvelope?

    /// Loads the last valid envelope from disk (fresh process / offline relaunch).
    public init(store: WatchCoachSuggestionStoring) {
        self.store = store
        self.current = Self.restore(from: store)
    }

    private static func restore(from store: WatchCoachSuggestionStoring) -> WatchCoachSuggestionEnvelope? {
        guard let data = store.loadData(), case .success(let envelope) = WatchCoachSuggestionEnvelope.decode(data) else {
            return nil
        }
        if let invalidated = store.loadInvalidatedAt(), envelope.issuedAt <= invalidated { return nil }
        return envelope
    }

    public var invalidatedAt: Date? { store.loadInvalidatedAt() }

    /// The envelope only if it may launch a suggestion right now.
    public func startable(now: Date) -> WatchCoachSuggestionEnvelope? {
        guard let current, current.isStartable(now: now) else { return nil }
        return current
    }

    public func apply(_ payload: WatchCoachSuggestionPayload, isHandshakeSnapshot: Bool) -> Outcome {
        switch payload {
        case .invalid:
            return .rejected
        case .absent:
            // A merged legacy context may omit it; only a handshake snapshot is authoritative.
            guard isHandshakeSnapshot else { return .ignored }
            guard current != nil || store.loadData() != nil else { return .removed }
            do { try store.deleteData() } catch { return .rejected }
            current = nil
            return .removed
        case .envelope(let envelope):
            if let invalidated = store.loadInvalidatedAt(), envelope.issuedAt <= invalidated { return .ignored }
            if let current {
                if envelope == current { return .applied }
                if envelope.issuedAt < current.issuedAt { return .ignored }
            }
            do { try store.saveData(try envelope.encoded()) } catch { return .rejected }
            current = envelope
            return .applied
        }
    }

    /// Watch history changed: unusable immediately, without waiting for the phone.
    public func invalidate(now: Date) {
        store.saveInvalidatedAt(now)
        current = nil
        try? store.deleteData()
    }
}

/// Posted by Watch-local strength logging/completion/discard/deletion so the Watch can make its
/// persisted Coach snapshot unusable immediately, before any phone round trip.
public enum WatchLocalHistoryMutation {
    public static let name = Notification.Name("cadence.watchLocalHistoryMutated")
    public static func notify() { NotificationCenter.default.post(name: name, object: nil) }
}
