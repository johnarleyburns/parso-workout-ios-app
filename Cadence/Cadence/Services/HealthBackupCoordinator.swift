import Foundation
import SwiftData
import CadenceCore

/// User-visible outcome of one durable Health backup drain. A queued item is
/// considered success only after the HealthKit adapter returns its object id;
/// failed items stay on disk with their retry time and plain-language error.
struct HealthBackupDrainReport: Equatable, Sendable {
    var attempted = 0
    var succeeded = 0
    var remaining = 0
    var lastError: String?
    var savedObjectIDs: [UUID: UUID] = [:]

    var isUpToDate: Bool { remaining == 0 && lastError == nil }
}

/// Coordinates the Core-only outbox with the platform HealthKit adapter. The
/// coordinator is main-actor isolated because SwiftData/UI callers hand it
/// summaries from the current scene; the durable queue itself is an actor so
/// foreground, background, and user-triggered retries cannot race file writes.
@MainActor
final class HealthBackupCoordinator {
    private let health: HealthDataProviding
    private let outbox: HealthOutboxStore
    private var draining = false

    private(set) var lastReport = HealthBackupDrainReport()

    init(health: HealthDataProviding, fileURL: URL? = nil) {
        self.health = health
        let url = fileURL ?? Self.defaultFileURL(isUITest: ProcessInfo.processInfo.arguments.contains("-uiTest"))
        self.outbox = HealthOutboxStore(fileURL: url)
    }

    func enqueueAndDrain(_ job: HealthBackupJob) async -> HealthBackupDrainReport {
        do {
            try await outbox.enqueue(HealthOutboxItem(job: job))
        } catch {
            lastReport = HealthBackupDrainReport(lastError: "Couldn’t queue Apple Health backup: \(error.localizedDescription)")
            return lastReport
        }
        return await drain()
    }

    /// Queues every HealthKit-representable row from the legacy store before
    /// the H5 split-store marker is written. This intentionally does not drain
    /// yet: the durable outbox must survive the restart that switches the app
    /// to the new local/sync configurations.
    func enqueueMigrationBackfill(from context: ModelContext) async throws -> Int {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let cardio = try context.fetch(FetchDescriptor<CardioWorkout>())
        let assessments = try context.fetch(FetchDescriptor<Assessment>())
        var queued = 0

        for session in sessions {
            guard let summary = HealthBackupEncoder.strengthSummary(for: session) else { continue }
            try await outbox.enqueue(HealthOutboxItem(job: .strength(summary)))
            queued += 1
        }
        for workout in cardio {
            try await outbox.enqueue(HealthOutboxItem(
                job: .cardio(HealthBackupEncoder.cardioSummary(for: workout))))
            queued += 1
        }
        for assessment in assessments {
            try await outbox.enqueue(HealthOutboxItem(
                job: .assessment(HealthBackupEncoder.assessmentPayload(for: assessment))))
            queued += 1
        }
        return queued
    }

    func drain() async -> HealthBackupDrainReport {
        guard !draining else { return lastReport }
        guard health.isHealthDataAvailable else {
            lastReport = (try? await pendingReport()) ?? HealthBackupDrainReport(lastError: "Apple Health is unavailable on this device.")
            return lastReport
        }

        draining = true
        defer { draining = false }
        var report = HealthBackupDrainReport()
        do {
            for item in try await outbox.due() {
                report.attempted += 1
                do {
                    let job = try item.decodeJob()
                    let objectID: UUID?
                    switch job {
                    case .strength(let summary):
                        objectID = await health.saveStrengthWorkout(summary)
                    case .cardio(let summary):
                        objectID = await health.saveCardioWorkout(summary)
                    case .assessment(let payload):
                        objectID = await health.saveAssessment(payload)
                    case .delete(let kind, let id, _):
                        objectID = await health.deleteHealthBackup(kind: kind, id: id) ? id : nil
                    }
                    if let objectID {
                        try await outbox.markSucceeded(item.id)
                        report.succeeded += 1
                        if item.operation == .upsert {
                            report.savedObjectIDs[item.entityID] = objectID
                        }
                    } else {
                        let message = "Apple Health did not accept this backup yet."
                        try await outbox.markFailed(item.id, error: message)
                        report.lastError = message
                    }
                } catch {
                    let message = "Backup could not be encoded: \(error.localizedDescription)"
                    try await outbox.markFailed(item.id, error: message)
                    report.lastError = message
                }
            }
            report.remaining = try await outbox.snapshot().items.count
        } catch {
            report.lastError = "Couldn’t read the Apple Health backup queue: \(error.localizedDescription)"
            report.remaining = (try? await outbox.snapshot().items.count) ?? 0
        }
        lastReport = report
        return report
    }

    private func pendingReport() async throws -> HealthBackupDrainReport {
        HealthBackupDrainReport(remaining: try await outbox.snapshot().items.count)
    }

    private static func defaultFileURL(isUITest: Bool) -> URL {
        if isUITest {
            return FileManager.default.temporaryDirectory.appendingPathComponent("cladiron-health-outbox.json")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("HealthOutbox.json")
    }
}
