import Foundation
import SwiftData
import CadenceCore

/// Durable idle-deadline record for a Watch-started/resumed **strength** workout. Persisted so a
/// process relaunch or suspended app cannot forget the deadline. Timeout arithmetic is owned by
/// `StrengthInactivityPolicy`; nothing here duplicates it.
public struct WatchStrengthInactivityRecord: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let startedAt: Date
    public var lastMeaningfulActivityAt: Date
    public let timeoutMinutes: Int
    public let sessionGeneration: UUID

    public init(sessionID: UUID, startedAt: Date, lastMeaningfulActivityAt: Date,
                timeoutMinutes: Int, sessionGeneration: UUID = UUID()) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.lastMeaningfulActivityAt = lastMeaningfulActivityAt
        self.timeoutMinutes = timeoutMinutes
        self.sessionGeneration = sessionGeneration
    }

    public var deadline: Date {
        StrengthInactivityPolicy.deadline(
            state: .init(lastMeaningfulActivityAt: lastMeaningfulActivityAt),
            timeoutMinutes: timeoutMinutes)
    }
}

/// Shown on the next Watch launch after an inactivity auto-end (Transparency HARD RULE).
public struct WatchStrengthInactivityNotice: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let endedAt: Date
    public let timeoutMinutes: Int
    public let keptSets: Bool

    public init(sessionID: UUID, endedAt: Date, timeoutMinutes: Int, keptSets: Bool) {
        self.sessionID = sessionID
        self.endedAt = endedAt
        self.timeoutMinutes = timeoutMinutes
        self.keptSets = keptSets
    }

    public var message: String {
        "Workout ended after \(timeoutMinutes) minutes inactive"
    }
}

/// Durable storage seam (Watch `UserDefaults` in production, a suite in tests).
public struct WatchStrengthInactivityStore: Sendable {
    public static let recordKey = "watch.strengthInactivity.record.v1"
    public static let noticeKey = "watch.strengthInactivity.notice.v1"
    /// nil = `UserDefaults.standard`. Held by name because `UserDefaults` is not `Sendable`.
    private let suiteName: String?
    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    public init(suiteName: String? = nil) { self.suiteName = suiteName }

    public func loadRecord() -> WatchStrengthInactivityRecord? {
        defaults.data(forKey: Self.recordKey).flatMap { try? JSONDecoder().decode(WatchStrengthInactivityRecord.self, from: $0) }
    }
    public func saveRecord(_ record: WatchStrengthInactivityRecord) {
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: Self.recordKey) }
    }
    public func clearRecord() { defaults.removeObject(forKey: Self.recordKey) }

    public func loadNotice() -> WatchStrengthInactivityNotice? {
        defaults.data(forKey: Self.noticeKey).flatMap { try? JSONDecoder().decode(WatchStrengthInactivityNotice.self, from: $0) }
    }
    public func saveNotice(_ notice: WatchStrengthInactivityNotice?) {
        if let notice, let data = try? JSONEncoder().encode(notice) {
            defaults.set(data, forKey: Self.noticeKey)
        } else {
            defaults.removeObject(forKey: Self.noticeKey)
        }
    }
}

/// Pure-ish watchdog logic over the durable record. Only `begin` and `recordActivity` move the
/// deadline; `evaluate` never does (so recovery, HR relay, HealthKit callbacks and screen
/// appearance cannot extend it).
public struct WatchStrengthInactivityTracker: Sendable {
    public enum Reconciliation: Equatable, Sendable {
        case noRecord
        /// Setting is off; the record (if any) is left alone and nothing ends.
        case disabled
        case waiting(until: Date)
        /// Overdue: finalize using the STORED deadline, never `now`.
        case finalize(WatchStrengthInactivityRecord, endedAt: Date)
    }

    public let store: WatchStrengthInactivityStore
    public init(store: WatchStrengthInactivityStore = WatchStrengthInactivityStore()) { self.store = store }

    public var record: WatchStrengthInactivityRecord? { store.loadRecord() }

    /// Creates the record once a Watch strength `WorkoutSession` exists. An existing record for the
    /// same session is kept untouched (a re-created view must not reset it). Returns nil when the
    /// auto-end setting is off.
    @discardableResult
    public func begin(sessionID: UUID, now: Date, timeoutMinutes: Int, enabled: Bool) -> WatchStrengthInactivityRecord? {
        guard enabled else { return nil }
        if let existing = store.loadRecord(), existing.sessionID == sessionID { return existing }
        var state = StrengthInactivityPolicy.State(lastMeaningfulActivityAt: now)
        state.record(.userStart, at: now)
        let record = WatchStrengthInactivityRecord(
            sessionID: sessionID, startedAt: now,
            lastMeaningfulActivityAt: state.lastMeaningfulActivityAt,
            timeoutMinutes: max(1, timeoutMinutes))
        store.saveRecord(record)
        return record
    }

    /// The only mutation path. Ignored once the deadline has already passed (the workout is
    /// logically over; reconciliation owns it) so a late gesture cannot resurrect it.
    @discardableResult
    public func recordActivity(_ event: StrengthActivityEvent, now: Date) -> WatchStrengthInactivityRecord? {
        guard var record = store.loadRecord(), now < record.deadline else { return nil }
        var state = StrengthInactivityPolicy.State(lastMeaningfulActivityAt: record.lastMeaningfulActivityAt)
        state.record(event, at: now)
        record.lastMeaningfulActivityAt = state.lastMeaningfulActivityAt
        store.saveRecord(record)
        return record
    }

    public func evaluate(now: Date, enabled: Bool) -> Reconciliation {
        guard let record = store.loadRecord() else { return .noRecord }
        switch StrengthInactivityPolicy.evaluate(
            state: .init(lastMeaningfulActivityAt: record.lastMeaningfulActivityAt),
            now: now, timeoutMinutes: record.timeoutMinutes, enabled: enabled) {
        case .end(let deadline): return .finalize(record, endedAt: deadline)
        case .continueWorkout: return enabled ? .waiting(until: record.deadline) : .disabled
        }
    }

    /// Clears only the record it was handed (a newer generation is never cleared by a stale caller).
    public func clear(matching generation: UUID? = nil) {
        guard let record = store.loadRecord() else { return }
        if let generation, record.sessionGeneration != generation { return }
        store.clearRecord()
    }
}

/// Finalizes the local strength `WorkoutSession` at the stored deadline. Idempotent; never touches
/// logged sets. A session with no sets is deleted, exactly like the explicit-Finish policy in
/// `WatchStrengthFlowModel.finish()`.
public enum WatchStrengthInactivityFinalizer {
    public enum Outcome: Equatable, Sendable { case finalized, discardedEmpty, alreadyEnded, missingSession }

    @MainActor
    public static func finalize(sessionID: UUID, endedAt: Date, now: Date,
                                context: ModelContext) -> Outcome {
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })
        descriptor.fetchLimit = 1
        guard let session = try? context.fetch(descriptor).first else { return .missingSession }
        guard session.endedAt == nil else { return .alreadyEnded }
        if session.orderedSets.isEmpty {
            context.delete(session)
            try? context.save()
            return .discardedEmpty
        }
        session.endedAt = endedAt
        session.cooldownSeconds = 0
        session.endReasonRaw = StrengthEndReason.inactivity.rawValue
        session.inactivityAutoEndedAt = now
        session.updatedAt = now
        try? context.save()
        return .finalized
    }
}
