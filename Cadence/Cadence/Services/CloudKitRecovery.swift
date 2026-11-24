import Foundation
import CloudKit
import SwiftData
import CadenceCore

/// Temporary recovery path for the 1184 incident. Uses the existing private
/// CloudKit container in a *separate* store, waits for its import, then merges
/// the downloaded rows into the local-only live store.
///
/// This file and the iCloud entitlement are recovery-build only. The shipping
/// App Store build removes both.

/// The Core Data / SwiftData mirroring container and zone. Reading them is
/// read-only and tells us whether the cloud copy actually contains workouts.
private let recoveryContainerID = "iCloud.guru.parso.cladiron.sync"
private let coreDataZoneName = "com.apple.coredata.cloudkit.zone"
private let recoveryTimedOut = "CLADIRON_RECOVERY_TIMEOUT"

@MainActor
enum CloudKitRecovery {

    struct Report {
        let downloadedSessions: Int
        let changedRecords: Int
        let liveSessionsBefore: Int
        let liveSessionsAfter: Int
        let inventory: String?
        let errors: [String]
        var recoveredAny: Bool { liveSessionsAfter > liveSessionsBefore || changedRecords > 0 }
    }

    struct Inventory: Sendable {
        let summary: String
        let workoutRecords: Int
    }

    // MARK: - Bounded phases

    /// Every CloudKit call is given a hard ceiling. A hung container query must
    /// never leave the screen on a spinner; the import still runs afterwards.
    private static func bounded<T: Sendable>(seconds: Double, fallback: T,
                                             _ operation: @escaping @Sendable () async -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            let gate = TimeoutGate()
            Task.detached {
                let value = await operation()
                if gate.claim() { continuation.resume(returning: value) }
            }
            Task.detached {
                try? await Task.sleep(for: .seconds(seconds))
                if gate.claim() { continuation.resume(returning: fallback) }
            }
        }
    }

    /// Distinguishes "no iCloud access" from an empty container.
    nonisolated static func accountProblem() async -> String? {
        let container = CKContainer(identifier: recoveryContainerID)
        guard container.containerIdentifier != nil else {
            return "This build is not authorized for the Cladiron iCloud container. Install the recovery build from TestFlight again."
        }
        do {
            switch try await container.accountStatus() {
            case .available:
                return nil
            case .noAccount:
                return "This device is not signed into iCloud. Sign in under Settings › Apple Account, then try again."
            case .restricted:
                return "iCloud is restricted on this device, so the Cladiron copy cannot be downloaded."
            case .temporarilyUnavailable:
                return "iCloud is temporarily unavailable. Try again in a few minutes."
            case .couldNotDetermine:
                return "iCloud could not determine this device’s account. Sign out and back into iCloud, then try again."
            @unknown default:
                return "iCloud returned an unknown account status."
            }
        } catch {
            return "iCloud is not available: \(error.localizedDescription)"
        }
    }

    /// Counts what the private database holds, per record type. Read-only:
    /// no save, no push.
    nonisolated static func inventory() async -> Inventory {
        let database = CKContainer(identifier: recoveryContainerID).privateCloudDatabase
        let coreDataZone = CKRecordZone.ID(zoneName: coreDataZoneName,
                                           ownerName: CKCurrentUserDefaultName)
        let types = ["CD_WorkoutSession", "CD_CardioWorkout", "CD_SetEntry", "CD_Assessment"]

        func count(in zoneID: CKRecordZone.ID) async throws -> [String: Int] {
            var counts: [String: Int] = [:]
            for type in types {
                let (results, _) = try await database.records(
                    matching: CKQuery(recordType: type, predicate: NSPredicate(value: true)),
                    inZoneWith: zoneID,
                    desiredKeys: nil,
                    resultsLimit: 100)
                counts[type] = results.count
            }
            return counts
        }

        do {
            let counts = try await count(in: coreDataZone)
            return Inventory(summary: describe(counts, zone: "store zone"), workoutRecords: counts["CD_WorkoutSession"] ?? 0)
        } catch {
            let coreError = error.localizedDescription
            do {
                let counts = try await count(in: CKRecordZone.default().zoneID)
                return Inventory(summary: describe(counts, zone: "default zone"), workoutRecords: counts["CD_WorkoutSession"] ?? 0)
            } catch {
                return Inventory(summary: "iCloud could not be read. Store zone: \(coreError). Default zone: \(error.localizedDescription)",
                                 workoutRecords: 0)
            }
        }
    }

    private nonisolated static func describe(_ counts: [String: Int], zone: String) -> String {
        let total = counts.values.reduce(0, +)
        guard total > 0 else {
            return "iCloud is reachable but the \(zone) holds no Cladiron records."
        }
        let parts = counts
            .filter { $0.value > 0 }
            .map { "\($0.key.replacingOccurrences(of: "CD_", with: "")) \($0.value)" }
            .joined(separator: ", ")
        return "iCloud \(zone): \(total) samples — \(parts)."
    }

    // MARK: - Recovery

    static func run(into live: ModelContainer,
                    progress: @MainActor @escaping (String) -> Void) async -> Report {
        let liveContext = ModelContext(live)
        let before = (try? liveContext.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0

        func failure(_ message: String, inventory: String? = nil) -> Report {
            Report(downloadedSessions: 0, changedRecords: 0,
                   liveSessionsBefore: before, liveSessionsAfter: before,
                   inventory: inventory, errors: [message])
        }

        progress("Checking your iCloud account…")
        let account: String? = await bounded(seconds: 15, fallback: recoveryTimedOut as String?) {
            await accountProblem()
        }
        if let account, account != recoveryTimedOut {
            return failure(account)
        }
        if account == recoveryTimedOut {
            progress("The iCloud account check timed out. Trying the import anyway…")
        }

        progress("Reading iCloud…")
        let cloud = await bounded(seconds: 45,
                                  fallback: Inventory(summary: "The iCloud inventory check timed out.",
                                                      workoutRecords: 0)) {
            await inventory()
        }
        progress(cloud.summary)

        // A persistent scratch store (not /tmp) keeps the CloudKit mirroring
        // actor from writing into a directory we delete underneath it, and lets
        // a second attempt resume instead of re-downloading everything.
        let supportDirectory = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                             in: .userDomainMask,
                                                             appropriateFor: nil,
                                                             create: true))
            ?? FileManager.default.temporaryDirectory
        let directory = supportDirectory.appendingPathComponent("CloudRecovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        progress("Opening the iCloud recovery store…")
        let schema = CadenceStore.schema
        let configuration = ModelConfiguration(schema: schema,
                                               url: directory.appendingPathComponent("CloudRecovery.store"),
                                               cloudKitDatabase: .private(containerID))
        let scratch: ModelContainer
        do {
            scratch = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            return failure("Could not open the iCloud recovery store: \(error.localizedDescription)",
                           inventory: cloud.summary)
        }

        var lastCount = 0
        var quietTicks = 0
        var downloaded = 0
        // Up to six minutes. CloudKit imports in batches; stop after the count
        // has been stable for ~10 seconds once something has arrived.
        for tick in 0..<180 {
            if Task.isCancelled { break }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                break
            }
            let count = (try? ModelContext(scratch).fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
            downloaded = max(downloaded, count)
            if count > 0, count == lastCount {
                quietTicks += 1
            } else {
                quietTicks = 0
            }
            lastCount = count
            progress(count == 0
                     ? "Waiting for iCloud to send your history…"
                     : "Downloaded \(count) workouts from iCloud…")
            if count > 0, quietTicks >= 5 { break }
            if count == 0, tick == 29 {
                progress("Still waiting for iCloud. Keep the app open, online, and signed into iCloud.")
            }
        }

        guard downloaded > 0 else {
            return failure("The recovery store imported no workouts. \(cloud.summary)",
                           inventory: cloud.summary)
        }

        progress("Merging \(downloaded) workouts into your local history…")
        do {
            let scratchContext = ModelContext(scratch)
            let archive = try NativeDatabaseExport.build(from: scratchContext)
            let changed = try NativeDatabaseExport.merge(archive, in: liveContext)
            try liveContext.save()
            let after = (try? liveContext.fetchCount(FetchDescriptor<WorkoutSession>())) ?? before
            return Report(downloadedSessions: downloaded, changedRecords: changed,
                          liveSessionsBefore: before, liveSessionsAfter: after,
                          inventory: cloud.summary, errors: [])
        } catch {
            return failure("Downloaded data could not be merged: \(error.localizedDescription)",
                           inventory: cloud.summary)
        }
    }
}

/// Ensures a continuation resumes exactly once when a bounded phase races its
/// timeout.
private final class TimeoutGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}
