import Foundation

/// Versioned, acknowledged phone→Watch settings/context synchronization.
///
/// `updateApplicationContext` only proves the phone *queued* a write. A snapshot is
/// confirmed solely by a matching `Ack` from the Watch. Everything here is pure
/// (clock and persistence injected) so it is testable headlessly.
///
/// Documented bounds:
/// - `ackTimeout` (120 s): an unacknowledged snapshot older than this is shown as stale.
/// - `reconcileInterval` (300 s): while a foreground app is in use, a confirmation older
///   than this is re-verified with a fresh revision (coalesced; never a busy poll).
/// - `minimumResendInterval` (30 s): lifecycle events (activation, reachability) cannot
///   re-send an unacknowledged snapshot more often than this.
/// - Retries back off exponentially from `ackTimeout`, capped at `maximumBackoff` (15 min).
public enum WatchSyncHandshake {
    public static let protocolVersion = 1
    public static let ackTimeout: TimeInterval = 120
    public static let reconcileInterval: TimeInterval = 300
    public static let minimumResendInterval: TimeInterval = 30
    public static let maximumBackoff: TimeInterval = 900

    public enum Key {
        public static let protocolVersion = "watchSync.protocolVersion"
        public static let revision = "watchSync.revision"
        public static let snapshotID = "watchSync.snapshotID"
        public static let createdAt = "watchSync.createdAt"
        public static let preferencesRevision = "watchSync.component.preferences"
        public static let customExercisesRevision = "watchSync.component.customExercises"
        public static let todayPlanRevision = "watchSync.component.todayPlan"
        public static let weekSummaryRevision = "watchSync.component.weekSummary"
        public static let coachSuggestionRevision = "watchSync.component.coachSuggestion"
        public static let cardioHistoryRevision = "watchSync.component.cardioHistory"
        /// Command value of an acknowledgement / status report sent Watch→phone.
        public static let ackCommand = "watch_sync_ack"
        public static let appliedRevision = "watchSync.appliedRevision"
        public static let appliedSnapshotID = "watchSync.appliedSnapshotID"
        public static let appliedAt = "watchSync.appliedAt"
    }

    /// Independent content fingerprints (stable across launches, never shown to users).
    public struct Components: Codable, Equatable, Sendable {
        public var preferences: String
        public var customExercises: String
        public var todayPlan: String
        public var weekSummary: String
        /// Identity of the shared Coach snapshot envelope; "" when none is published (removal).
        public var coachSuggestion: String
        /// Fingerprint of the phone's cardio history snapshot; "" when no snapshot is published.
        /// A history-only change alters this, so the handshake never coalesces it away.
        public var cardioHistory: String

        public init(preferences: String, customExercises: String, todayPlan: String, weekSummary: String,
                    coachSuggestion: String = "", cardioHistory: String = "") {
            self.coachSuggestion = coachSuggestion
            self.cardioHistory = cardioHistory
            self.preferences = preferences
            self.customExercises = customExercises
            self.todayPlan = todayPlan
            self.weekSummary = weekSummary
        }

        /// Derives fingerprints from a context dictionary. `updatedAt` stamps and the
        /// envelope itself are excluded so only real content changes alter a fingerprint.
        public init(context: [String: Any]) {
            func part(_ include: (String) -> Bool) -> String {
                let sub = context.filter { include($0.key) && !$0.key.hasSuffix("updatedAt") }
                return WatchSyncFingerprint.canonicalHash(sub)
            }
            preferences = part { $0.hasPrefix("settings.") || $0 == WatchSync.Key.recentPartners }
            customExercises = part { $0 == WatchSync.Key.customExercises }
            todayPlan = part { $0.hasPrefix("todayPlan.") || $0 == WatchSync.Key.sentWorkouts }
            weekSummary = part { $0.hasPrefix("week.") }
            // Hash the envelope bytes (not Data's weak checksum); no key means removal ("").
            let coach = context.filter {
                $0.key == WatchSync.Key.coachSuggestionSnapshot
            }.mapValues { value -> Any in
                (value as? Data).map { WatchSyncFingerprint.canonicalHash($0.base64EncodedString()) } ?? value
            }
            coachSuggestion = coach.isEmpty ? "" : WatchSyncFingerprint.canonicalHash(coach)
            // The updatedAt stamp is excluded; an absent key (older phone / not yet built) is "".
            cardioHistory = context[WatchSync.Key.cardioHistoryItems].map {
                WatchSyncFingerprint.canonicalHash($0)
            } ?? ""
        }

        private enum CodingKeys: String, CodingKey {
            case preferences, customExercises, todayPlan, weekSummary, coachSuggestion, cardioHistory
        }

        /// Ledgers persisted before the Coach component existed decode with "".
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            preferences = try c.decode(String.self, forKey: .preferences)
            customExercises = try c.decode(String.self, forKey: .customExercises)
            todayPlan = try c.decode(String.self, forKey: .todayPlan)
            weekSummary = try c.decode(String.self, forKey: .weekSummary)
            coachSuggestion = try c.decodeIfPresent(String.self, forKey: .coachSuggestion) ?? ""
            cardioHistory = try c.decodeIfPresent(String.self, forKey: .cardioHistory) ?? ""
        }
    }

    public struct Envelope: Codable, Equatable, Sendable {
        public var protocolVersion: Int
        public var revision: Int
        public var snapshotID: UUID
        public var createdAt: Date
        public var components: Components

        public init(protocolVersion: Int = WatchSyncHandshake.protocolVersion, revision: Int,
                    snapshotID: UUID = UUID(), createdAt: Date, components: Components) {
            self.protocolVersion = protocolVersion
            self.revision = revision
            self.snapshotID = snapshotID
            self.createdAt = createdAt
            self.components = components
        }

        public var contextEntries: [String: Any] {
            [Key.protocolVersion: protocolVersion,
             Key.revision: revision,
             Key.snapshotID: snapshotID.uuidString,
             Key.createdAt: createdAt,
             Key.preferencesRevision: components.preferences,
             Key.customExercisesRevision: components.customExercises,
             Key.todayPlanRevision: components.todayPlan,
             Key.weekSummaryRevision: components.weekSummary,
             Key.coachSuggestionRevision: components.coachSuggestion,
             Key.cardioHistoryRevision: components.cardioHistory]
        }

        /// Returns nil for legacy (pre-handshake) contexts.
        public init?(context: [String: Any]) {
            guard let version = context[Key.protocolVersion] as? Int,
                  let revision = context[Key.revision] as? Int,
                  let idString = context[Key.snapshotID] as? String,
                  let id = UUID(uuidString: idString) else { return nil }
            self.init(protocolVersion: version, revision: revision, snapshotID: id,
                      createdAt: (context[Key.createdAt] as? Date) ?? Date(timeIntervalSince1970: 0),
                      components: Components(
                        preferences: context[Key.preferencesRevision] as? String ?? "",
                        customExercises: context[Key.customExercisesRevision] as? String ?? "",
                        todayPlan: context[Key.todayPlanRevision] as? String ?? "",
                        weekSummary: context[Key.weekSummaryRevision] as? String ?? "",
                        coachSuggestion: context[Key.coachSuggestionRevision] as? String ?? "",
                        cardioHistory: context[Key.cardioHistoryRevision] as? String ?? ""))
        }

        public static func stripping(_ context: [String: Any]) -> [String: Any] {
            var copy = context
            for key in [Key.protocolVersion, Key.revision, Key.snapshotID, Key.createdAt,
                        Key.preferencesRevision, Key.customExercisesRevision,
                        Key.todayPlanRevision, Key.weekSummaryRevision, Key.coachSuggestionRevision,
                        Key.cardioHistoryRevision] {
                copy.removeValue(forKey: key)
            }
            return copy
        }
    }

    /// Watch→phone acknowledgement (also used as a status report: `snapshotID` nil = unknown).
    public struct Ack: Equatable, Sendable {
        public var protocolVersion: Int
        public var revision: Int
        public var snapshotID: UUID?
        public var components: Components?

        public init(protocolVersion: Int = WatchSyncHandshake.protocolVersion, revision: Int,
                    snapshotID: UUID?, components: Components?) {
            self.protocolVersion = protocolVersion
            self.revision = revision
            self.snapshotID = snapshotID
            self.components = components
        }

        public var message: [String: Any] {
            var m: [String: Any] = [WatchSync.Key.command: Key.ackCommand,
                                    Key.protocolVersion: protocolVersion,
                                    Key.appliedRevision: revision]
            if let snapshotID { m[Key.appliedSnapshotID] = snapshotID.uuidString }
            if let components {
                m[Key.preferencesRevision] = components.preferences
                m[Key.customExercisesRevision] = components.customExercises
                m[Key.todayPlanRevision] = components.todayPlan
                m[Key.weekSummaryRevision] = components.weekSummary
                m[Key.coachSuggestionRevision] = components.coachSuggestion
                m[Key.cardioHistoryRevision] = components.cardioHistory
            }
            return m
        }

        public init?(message: [String: Any]) {
            guard message[WatchSync.Key.command] as? String == Key.ackCommand,
                  let version = message[Key.protocolVersion] as? Int,
                  let revision = message[Key.appliedRevision] as? Int else { return nil }
            let comps: Components? = (message[Key.preferencesRevision] as? String).map {
                Components(preferences: $0,
                           customExercises: message[Key.customExercisesRevision] as? String ?? "",
                           todayPlan: message[Key.todayPlanRevision] as? String ?? "",
                           weekSummary: message[Key.weekSummaryRevision] as? String ?? "",
                           coachSuggestion: message[Key.coachSuggestionRevision] as? String ?? "",
                           cardioHistory: message[Key.cardioHistoryRevision] as? String ?? "")
            }
            self.init(protocolVersion: version, revision: revision,
                      snapshotID: (message[Key.appliedSnapshotID] as? String).flatMap(UUID.init(uuidString:)),
                      components: comps)
        }
    }

    /// Message the Watch sends to ask for a fresh snapshot, carrying what it has applied.
    public static func requestMessage(applied: WatchSyncAppliedRecord?) -> [String: Any] {
        var m = WatchSync.requestSettingsSyncMessage()
        m[Key.protocolVersion] = protocolVersion
        if let applied { m[Key.appliedRevision] = applied.revision }
        return m
    }
}

/// Stable (cross-launch) FNV-1a hashing; `Hasher` is randomly seeded per process.
public enum WatchSyncFingerprint {
    public static func canonicalHash(_ value: Any) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in canonical(value).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    static func canonical(_ value: Any) -> String {
        switch value {
        case let d as [String: Any]:
            return "{" + d.keys.sorted().map { "\($0):\(canonical(d[$0]!))" }.joined(separator: ",") + "}"
        case let a as [Any]:
            return "[" + a.map(canonical).joined(separator: ",") + "]"
        case let s as String: return "s\"\(s)\""
        case let b as Bool: return "b\(b)"
        case let i as Int: return "i\(i)"
        case let n as Double: return "n\(n)"
        case let date as Date: return "d\(date.timeIntervalSince1970)"
        case let data as Data: return "x\(data.count):\(data.reduce(0) { ($0 &* 31) &+ Int($1) })"
        default: return "?\(value)"
        }
    }
}

/// What the Watch last applied; persisted on the Watch.
public struct WatchSyncAppliedRecord: Codable, Equatable, Sendable {
    public var revision: Int
    public var snapshotID: UUID
    public var protocolVersion: Int
    public var components: WatchSyncHandshake.Components

    public init(revision: Int, snapshotID: UUID, protocolVersion: Int = WatchSyncHandshake.protocolVersion,
                components: WatchSyncHandshake.Components) {
        self.revision = revision
        self.snapshotID = snapshotID
        self.protocolVersion = protocolVersion
        self.components = components
    }

    public var ack: WatchSyncHandshake.Ack {
        .init(protocolVersion: protocolVersion, revision: revision, snapshotID: snapshotID, components: components)
    }
}

/// Watch-side decision for an incoming snapshot.
public enum WatchSyncReceiveDecision: Equatable, Sendable {
    /// Newer than anything applied: apply atomically, persist, then acknowledge.
    case apply
    /// Same snapshot seen before: acknowledge again, do not re-apply side effects.
    case duplicate
    /// Older than what is applied: never overwrite newer state; report status instead.
    case stale
    /// Unsupported protocol version: keep current state, report so the phone can show it.
    case incompatible
    /// Pre-handshake context: apply as before, but ask the phone for a handshake snapshot.
    case legacy

    public static func decide(context: [String: Any], applied: WatchSyncAppliedRecord?) -> WatchSyncReceiveDecision {
        guard let envelope = WatchSyncHandshake.Envelope(context: context) else {
            // A context with a protocol version we cannot parse is not "legacy".
            return context[WatchSyncHandshake.Key.protocolVersion] != nil ? .incompatible : .legacy
        }
        guard envelope.protocolVersion == WatchSyncHandshake.protocolVersion else { return .incompatible }
        guard let applied else { return .apply }
        if envelope.revision == applied.revision && envelope.snapshotID == applied.snapshotID { return .duplicate }
        return envelope.revision > applied.revision ? .apply : .stale
    }
}

public protocol WatchSyncLedgerStore: AnyObject {
    func load() -> WatchSyncLedger?
    func save(_ ledger: WatchSyncLedger)
}

public final class UserDefaultsWatchSyncLedgerStore: WatchSyncLedgerStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "watchSync.ledger.v1") {
        self.defaults = defaults
        self.key = key
    }
    public func load() -> WatchSyncLedger? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WatchSyncLedger.self, from: $0) }
    }
    public func save(_ ledger: WatchSyncLedger) {
        if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: key) }
    }
}

/// Persisted phone-side state. Codable with defaults so older/newer stores decode.
public struct WatchSyncLedger: Codable, Equatable, Sendable {
    public var lastIssuedRevision = 0
    public var pending: WatchSyncHandshake.Envelope?
    public var pendingSince: Date?
    public var lastAttemptAt: Date?
    public var attempts = 0
    /// Handed to WatchConnectivity (vs. only built locally).
    public var pendingWritten = false
    public var lastConfirmedRevision: Int?
    public var lastConfirmedSnapshotID: UUID?
    public var lastConfirmedAt: Date?
    public var lastConfirmedComponents: WatchSyncHandshake.Components?
    public var failure: WatchSyncFailure?
    public var isReconciling = false
    public init() {}
}

public enum WatchSyncFailure: String, Codable, Equatable, Sendable {
    case writeFailed
    case incompatibleVersion
    case settingsUnavailable
}

public enum WatchSyncTrigger: String, Sendable {
    case contentChanged, activation, installed, reachability, periodic
    case manual, watchRequest, workoutBoundary, retry

    /// Triggers that must produce a fresh revision regardless of freshness.
    var forcesRevision: Bool { self == .manual || self == .watchRequest || self == .installed }
}

public enum WatchSyncState: Equatable, Sendable {
    case notInstalled
    case activating
    case upToDate(confirmedAt: Date)
    case queued(revision: Int, since: Date)
    case awaitingWatch(revision: Int, since: Date)
    case reconciling
    case stale(lastConfirmedAt: Date?)
    case failedRecoverably(reason: WatchSyncFailure, lastConfirmedAt: Date?)

    public var isInProgress: Bool {
        switch self {
        case .queued, .awaitingWatch, .reconciling: return true
        default: return false
        }
    }

    public var isFailure: Bool {
        if case .failedRecoverably = self { return true }
        return false
    }

    public var canRetry: Bool {
        switch self {
        case .stale, .failedRecoverably, .upToDate: return true
        default: return false
        }
    }

    public var summaryText: String {
        switch self {
        case .notInstalled: return String(localized: "Watch app not installed", bundle: .module)
        case .activating: return String(localized: "Connecting to Apple Watch…", bundle: .module)
        case .upToDate: return String(localized: "Up to date", bundle: .module)
        case .queued: return String(localized: "Pending", bundle: .module)
        case .awaitingWatch: return String(localized: "Waiting for Apple Watch", bundle: .module)
        case .reconciling: return String(localized: "Checking with Apple Watch…", bundle: .module)
        case .stale: return String(localized: "Not confirmed", bundle: .module)
        case .failedRecoverably: return String(localized: "Needs attention", bundle: .module)
        }
    }

    /// Plain-language recovery text; never exposes revisions, IDs or fingerprints.
    public var detailText: String {
        switch self {
        case .notInstalled:
            return String(localized: "Install Cladiron on your Apple Watch to sync settings.", bundle: .module)
        case .activating:
            return String(localized: "Waiting for the connection to your Apple Watch to start.", bundle: .module)
        case .upToDate(let date):
            return String(localized: "Your Apple Watch confirmed these settings \(Self.relative(date)).", bundle: .module)
        case .queued, .awaitingWatch:
            return String(localized: "Settings are queued. Open Cladiron on your Apple Watch to finish; they stay saved on this iPhone meanwhile.", bundle: .module)
        case .reconciling:
            return String(localized: "Comparing what your Apple Watch has with this iPhone.", bundle: .module)
        case .stale:
            return String(localized: "Your Apple Watch hasn't confirmed the latest settings. Cladiron will retry automatically, or tap Sync now.", bundle: .module)
        case .failedRecoverably(let reason, _):
            switch reason {
            case .writeFailed:
                return String(localized: "The iPhone couldn't queue the update. Cladiron will retry, or tap Retry. Settings still work offline.", bundle: .module)
            case .incompatibleVersion:
                return String(localized: "The Cladiron version on your Apple Watch differs from this iPhone. Update both apps; your current settings are unchanged.", bundle: .module)
            case .settingsUnavailable:
                return String(localized: "Settings aren't ready yet. Cladiron will retry shortly.", bundle: .module)
            }
        }
    }

    /// Combined single string for VoiceOver and compact rows.
    public func accessibilityText(lastConfirmedAt: Date?) -> String {
        var parts = [summaryText, detailText]
        if let lastConfirmedAt, !{ if case .upToDate = self { return true } else { return false } }() {
            parts.append(String(localized: "Last confirmed by Apple Watch \(Self.relative(lastConfirmedAt)).", bundle: .module))
        }
        return parts.joined(separator: ". ")
    }

    public func settingsText(lastSyncAt: Date?) -> String {
        if case .upToDate(let date) = self {
            return String(localized: "Up to date, \(Self.relative(date))", bundle: .module)
        }
        return summaryText
    }

    public var toastText: String? {
        switch self {
        case .upToDate: return String(localized: "Watch confirmed", bundle: .module)
        case .failedRecoverably: return String(localized: "Watch sync needs attention", bundle: .module)
        case .stale: return String(localized: "Watch hasn't confirmed", bundle: .module)
        default: return nil
        }
    }

    /// "Last synced" means the last Watch *confirmation*, never a local write.
    public static func lastConfirmedText(_ date: Date?) -> String {
        guard let date else { return String(localized: "Never confirmed", bundle: .module) }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 5 { return String(localized: "just now", bundle: .module) }
        if seconds < 60 { return String(localized: "\(seconds)s ago", bundle: .module) }
        if seconds < 3600 { return String(localized: "\(seconds / 60)m ago", bundle: .module) }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

public enum WatchSyncAckOutcome: Equatable, Sendable {
    case confirmed
    case duplicate
    /// Older/unrelated revision or snapshot: ignored, cannot confirm the pending one.
    case ignored
    /// Watch reports a revision the phone never issued: resend the latest complete snapshot.
    case watchAhead
    /// Watch has an older revision than the phone's latest: resend.
    case watchBehind
    case incompatible
}

/// Serialized coordinator state machine for the phone side.
public final class WatchSyncTracker {
    public private(set) var ledger: WatchSyncLedger
    private let store: WatchSyncLedgerStore
    private let clock: () -> Date
    /// Pre-handshake "last synced" value; shown to nobody and never counted as confirmed.
    public let legacyLastSyncAt: Date?

    public init(store: WatchSyncLedgerStore, clock: @escaping () -> Date = Date.init,
                legacyLastSyncAt: Date? = nil) {
        self.store = store
        self.clock = clock
        self.legacyLastSyncAt = legacyLastSyncAt
        self.ledger = store.load() ?? WatchSyncLedger()
    }

    public var lastConfirmedAt: Date? { ledger.lastConfirmedAt }

    private func persist() { store.save(ledger) }

    private func retryDelay() -> TimeInterval {
        min(WatchSyncHandshake.maximumBackoff,
            WatchSyncHandshake.ackTimeout * pow(2, Double(max(0, ledger.attempts - 1))))
    }

    /// Cheap pre-check (before building a payload): may this trigger produce a write now?
    public func mayReconcile(_ trigger: WatchSyncTrigger) -> Bool {
        if trigger == .contentChanged { return true }
        let now = clock()
        if trigger.forcesRevision { return true }
        if ledger.pending != nil {
            guard let last = ledger.lastAttemptAt else { return true }
            let elapsed = now.timeIntervalSince(last)
            switch trigger {
            case .periodic, .retry:
                return elapsed >= retryDelay()
            default:
                return elapsed >= WatchSyncHandshake.minimumResendInterval
            }
        }
        if ledger.failure == .incompatibleVersion { return false }
        if let confirmed = ledger.lastConfirmedAt {
            return now.timeIntervalSince(confirmed) >= WatchSyncHandshake.reconcileInterval
        }
        return true
    }

    /// Decide whether a snapshot with these components must be written; returns the envelope
    /// to stamp into the context, or nil when the write is coalesced away.
    public func prepare(components: WatchSyncHandshake.Components, trigger: WatchSyncTrigger) -> WatchSyncHandshake.Envelope? {
        let now = clock()
        let changed = components != (ledger.pending?.components ?? ledger.lastConfirmedComponents)
        if !changed {
            // Unchanged content never re-sends on its own, but an unacknowledged or
            // unconfirmed revision is still re-verified by the lifecycle triggers.
            if trigger == .contentChanged || !mayReconcile(trigger) { return nil }
        }
        ledger.lastIssuedRevision += 1
        let envelope = WatchSyncHandshake.Envelope(revision: ledger.lastIssuedRevision, createdAt: now,
                                                   components: components)
        if ledger.pending == nil || changed { ledger.pendingSince = now }
        if changed { ledger.attempts = 0 }
        ledger.attempts += 1
        ledger.pending = envelope
        ledger.pendingWritten = false
        ledger.lastAttemptAt = now
        ledger.isReconciling = trigger == .watchRequest || trigger == .periodic
        if ledger.failure != .incompatibleVersion || trigger.forcesRevision { ledger.failure = nil }
        persist()
        return envelope
    }

    public func markWritten(revision: Int) {
        guard ledger.pending?.revision == revision else { return }
        ledger.pendingWritten = true
        persist()
    }

    public func markWriteFailed(revision: Int, reason: WatchSyncFailure = .writeFailed) {
        guard ledger.pending?.revision == revision else { return }
        ledger.failure = reason
        persist()
    }

    public func markSettingsUnavailable() {
        ledger.failure = .settingsUnavailable
        persist()
    }

    @discardableResult
    public func receive(ack: WatchSyncHandshake.Ack) -> WatchSyncAckOutcome {
        guard ack.protocolVersion == WatchSyncHandshake.protocolVersion else {
            ledger.failure = .incompatibleVersion
            persist()
            return .incompatible
        }
        if ledger.failure == .incompatibleVersion { ledger.failure = nil }
        if ack.revision > ledger.lastIssuedRevision {
            // Phone state was lost or the Watch holds an unknown snapshot: never trust it.
            ledger.lastIssuedRevision = ack.revision
            ledger.isReconciling = true
            persist()
            return .watchAhead
        }
        if let pending = ledger.pending, ack.revision == pending.revision {
            guard ack.snapshotID == pending.snapshotID else { return .ignored }
            ledger.lastConfirmedRevision = pending.revision
            ledger.lastConfirmedSnapshotID = pending.snapshotID
            ledger.lastConfirmedComponents = pending.components
            ledger.lastConfirmedAt = clock()
            ledger.pending = nil
            ledger.pendingSince = nil
            ledger.pendingWritten = false
            ledger.attempts = 0
            ledger.failure = nil
            ledger.isReconciling = false
            persist()
            return .confirmed
        }
        if ack.revision == ledger.lastConfirmedRevision, ack.snapshotID == ledger.lastConfirmedSnapshotID,
           ack.snapshotID != nil { return .duplicate }
        // An older ack while a newer snapshot is pending, or a status report with no snapshot.
        if ack.snapshotID == nil, ack.revision < ledger.lastIssuedRevision, ledger.pending == nil,
           ack.revision != ledger.lastConfirmedRevision {
            ledger.isReconciling = true
            persist()
            return .watchBehind
        }
        return .ignored
    }

    /// Watch asked for a snapshot (status carries what it has applied).
    public func receiveWatchRequest(appliedRevision: Int?, protocolVersion: Int?) -> WatchSyncAckOutcome {
        if let protocolVersion, protocolVersion != WatchSyncHandshake.protocolVersion {
            ledger.failure = .incompatibleVersion
            persist()
            return .incompatible
        }
        if let appliedRevision, appliedRevision > ledger.lastIssuedRevision {
            ledger.lastIssuedRevision = appliedRevision
            persist()
            return .watchAhead
        }
        return .watchBehind
    }

    public func state(now: Date? = nil, installed: Bool, activated: Bool) -> WatchSyncState {
        let now = now ?? clock()
        guard installed else { return .notInstalled }
        guard activated else { return .activating }
        if let failure = ledger.failure { return .failedRecoverably(reason: failure, lastConfirmedAt: ledger.lastConfirmedAt) }
        if let pending = ledger.pending, let since = ledger.pendingSince {
            if now.timeIntervalSince(ledger.lastAttemptAt ?? since) >= WatchSyncHandshake.ackTimeout {
                return .stale(lastConfirmedAt: ledger.lastConfirmedAt)
            }
            if ledger.isReconciling { return .reconciling }
            return ledger.pendingWritten
                ? .awaitingWatch(revision: pending.revision, since: since)
                : .queued(revision: pending.revision, since: since)
        }
        if let confirmed = ledger.lastConfirmedAt { return .upToDate(confirmedAt: confirmed) }
        return .stale(lastConfirmedAt: nil)
    }
}
