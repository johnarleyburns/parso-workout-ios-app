import Foundation

/// Identity reserved *before* the Watch preflight starts, so the eventual
/// phone-started strength `WorkoutSession` reuses it. A reservation is not a
/// workout: it never appears in history or This Week.
public struct WatchHRPreflightReservation: Codable, Equatable, Sendable {
    public var phoneWorkoutSessionID: UUID
    /// Identifies this capture attempt; a delayed packet from another epoch
    /// can never bind to it.
    public var captureEpoch: UUID
    public var reservedAt: Date
    /// Every real pre-adoption reading, in arrival order, keyed by immutable ID.
    public var buffered: [WatchHRObservation] = []
    public init(phoneWorkoutSessionID: UUID = UUID(), captureEpoch: UUID = UUID(), reservedAt: Date) {
        self.phoneWorkoutSessionID = phoneWorkoutSessionID
        self.captureEpoch = captureEpoch
        self.reservedAt = reservedAt
    }
}

public enum WatchHRPreflightBufferOutcome: Equatable, Sendable {
    case buffered, duplicate
    /// The preflight was cancelled or already adopted: the reading is dropped
    /// (and may be acknowledged so the Watch stops resending it).
    case tombstoned
    /// Not this ledger's identity: reject, never reassign.
    case unknown
}

/// Pure, persistable state machine for the pre-adoption capture window.
public struct WatchHRPreflightLedger: Codable, Equatable, Sendable {
    public static let maxBuffered = 5_000
    public static let maxTombstones = 16
    public static let staleAfter: TimeInterval = 2 * 3_600

    public private(set) var reservation: WatchHRPreflightReservation?
    /// Session IDs of cancelled/adopted/expired preflights.
    public private(set) var tombstones: [UUID] = []

    public init() {}

    /// Returns the live reservation, creating one when none exists or the
    /// previous one went stale (which is tombstoned first).
    @discardableResult
    public mutating func reserve(now: Date = Date()) -> WatchHRPreflightReservation {
        if let current = reservation {
            if now.timeIntervalSince(current.reservedAt) < Self.staleAfter { return current }
            tombstone(current.phoneWorkoutSessionID)
        }
        let fresh = WatchHRPreflightReservation(reservedAt: now)
        reservation = fresh
        return fresh
    }

    public func isTombstoned(_ sessionID: UUID) -> Bool { tombstones.contains(sessionID) }

    /// Cancels the preflight: buffered readings are discarded and the ID can
    /// never be adopted or fed again. Returns the cancelled session ID.
    @discardableResult
    public mutating func cancel() -> UUID? {
        guard let current = reservation else { return nil }
        tombstone(current.phoneWorkoutSessionID)
        reservation = nil
        return current.phoneWorkoutSessionID
    }

    public mutating func buffer(_ observation: WatchHRObservation, sessionID: UUID) -> WatchHRPreflightBufferOutcome {
        if isTombstoned(sessionID) { return .tombstoned }
        guard var current = reservation, current.phoneWorkoutSessionID == sessionID else { return .unknown }
        guard !current.buffered.contains(where: { $0.observationID == observation.observationID
            || ($0.sampleID != nil && $0.sampleID == observation.sampleID) }) else { return .duplicate }
        current.buffered.append(observation)
        if current.buffered.count > Self.maxBuffered { current.buffered.removeFirst(current.buffered.count - Self.maxBuffered) }
        reservation = current
        return .buffered
    }

    /// Binds the reservation to the real workout. Only the reserved ID adopts;
    /// returns the buffered readings inside `start...end` (deduplicated), or
    /// nil when `sessionID` is not the reservation. The reservation is consumed.
    public mutating func adopt(sessionID: UUID, start: Date, end: Date) -> [WatchHRObservation]? {
        guard let current = reservation, current.phoneWorkoutSessionID == sessionID else { return nil }
        reservation = nil
        tombstone(sessionID)
        let lower = start.timeIntervalSince1970, upper = end.timeIntervalSince1970
        var seen = Set<UUID>()
        return current.buffered
            .filter { $0.sampleEnd >= lower && $0.sampleEnd <= upper }
            .filter { seen.insert($0.observationID).inserted }
            .sorted { $0.sampleEnd < $1.sampleEnd }
    }

    private mutating func tombstone(_ id: UUID) {
        guard !tombstones.contains(id) else { return }
        tombstones.append(id)
        if tombstones.count > Self.maxTombstones { tombstones.removeFirst(tombstones.count - Self.maxTombstones) }
    }
}
