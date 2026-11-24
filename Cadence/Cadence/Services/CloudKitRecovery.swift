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
@MainActor
enum CloudKitRecovery {
    static let containerID = "iCloud.guru.parso.cladiron.sync"
    /// The zone Core Data / SwiftData mirroring uses for every store in the
    /// container. Enumerating it is read-only and tells us whether the cloud
    /// copy actually contains workouts.
    static let coreDataZoneName = "com.apple.coredata.cloudkit.zone"

    struct Report {
        let downloadedSessions: Int
        let changedRecords: Int
        let liveSessionsBefore: Int
        let liveSessionsAfter: Int
        let inventory: String?
        let errors: [String]
        var recoveredAny: Bool { liveSessionsAfter > liveSessionsBefore || changedRecords > 0 }
    }

    /// Distinguishes "no iCloud access" from an empty container before we wait
    /// five minutes for an import that cannot happen.
    static func preflight() async -> String? {
        let container = CKContainer(identifier: containerID)
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

    /// Counts what the private database actually holds, per record type, by
    /// enumerating every zone. Read-only: no save, no push.
    static func inventory() async -> (summary: String, workoutRecords: Int) {
        let database = CKContainer(identifier: containerID).privateCloudDatabase
        var zoneIDs: [CKRecordZone.ID]
        var setupError: String?
        do {
            var zones = try await database.allRecordZones()
            zones.append(CKRecordZone.default())
            zoneIDs = zones.map(\.zoneID)
        } catch {
            zoneIDs = [CKRecordZone.ID(zoneName: coreDataZoneName,
                                       ownerName: CKCurrentUserDefaultName)]
            setupError = error.localizedDescription
        }
        let box = InventoryBox()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let operation = CKFetchRecordZoneChangesOperation()
            operation.recordZoneIDs = zoneIDs
            var configurations: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
            for zoneID in zoneIDs {
                configurations[zoneID] = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            }
            operation.configurationsByRecordZoneID = configurations
            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result { box.add(record.recordType) }
            }
            operation.recordZoneFetchResultBlock = { _, result in
                if case .failure(let error) = result { box.fail(error) }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                if case .failure(let error) = result { box.fail(error) }
                continuation.resume()
            }
            database.add(operation)
        }
        let snapshot = box.snapshot()
        if let error = snapshot.error ?? setupError, snapshot.counts.isEmpty {
            return ("iCloud could not be read: \(error)", 0)
        }
        guard !snapshot.counts.isEmpty else {
            return ("iCloud has \(zoneIDs.count) zone(s) but no Cladiron records in them.", 0)
        }
        let total = snapshot.counts.values.reduce(0, +)
        let workouts = snapshot.counts["CD_WorkoutSession"] ?? 0
        let top = snapshot.counts
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        return ("iCloud has \(total) records across \(zoneIDs.count) zone(s) (workouts: \(workouts)). Largest types: \(top).", workouts)
    }

    static func run(into live: ModelContainer,
                    progress: @MainActor @escaping (String) -> Void) async -> Report {
        let liveContext = ModelContext(live)
        let before = (try? liveContext.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
        // A persistent scratch store (not /tmp) keeps the CloudKit mirroring
        // actor from writing into a directory we delete underneath it, and lets
        // a second attempt resume instead of re-downloading everything.
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: true))
            ?? FileManager.default.temporaryDirectory
        let directory = support.appendingPathComponent("CloudRecovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        progress("Checking what iCloud holds…")
        let cloud = await inventory()

        let storeURL = directory.appendingPathComponent("CloudRecovery.store")
        let schema = CadenceStore.schema
        let configuration = ModelConfiguration(schema: schema, url: storeURL,
                                               cloudKitDatabase: .private(containerID))
        let scratch: ModelContainer
        do {
            scratch = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            return Report(downloadedSessions: 0, changedRecords: 0,
                          liveSessionsBefore: before, liveSessionsAfter: before,
                          inventory: cloud.summary,
                          errors: ["Could not open the iCloud recovery store: \(error.localizedDescription)"])
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
            return Report(downloadedSessions: 0, changedRecords: 0,
                          liveSessionsBefore: before, liveSessionsAfter: before,
                          inventory: cloud.summary,
                          errors: ["The recovery store imported no workouts. \(cloud.summary)"])
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
            return Report(downloadedSessions: downloaded, changedRecords: 0,
                          liveSessionsBefore: before, liveSessionsAfter: before,
                          inventory: cloud.summary,
                          errors: ["Downloaded data could not be merged: \(error.localizedDescription)"])
        }
    }
}

/// Small thread-safe accumulator for CloudKit's background callbacks.
private final class InventoryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var error: String?

    func add(_ recordType: String) {
        lock.lock()
        counts[recordType, default: 0] += 1
        lock.unlock()
    }

    func fail(_ error: Error) {
        lock.lock()
        if self.error == nil { self.error = error.localizedDescription }
        lock.unlock()
    }

    func snapshot() -> (counts: [String: Int], error: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (counts, error)
    }
}
