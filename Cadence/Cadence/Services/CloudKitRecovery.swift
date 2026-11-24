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

    struct Report {
        let downloadedSessions: Int
        let changedRecords: Int
        let liveSessionsBefore: Int
        let liveSessionsAfter: Int
        let errors: [String]
        var recoveredAny: Bool { liveSessionsAfter > liveSessionsBefore || changedRecords > 0 }
    }

    /// Distinguishes "no iCloud access / wrong environment" from an empty
    /// container before we wait five minutes for an import that cannot happen.
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
            case .couldNotFindAccount:
                return "iCloud could not find this device’s account. Sign out and back into iCloud, then try again."
            @unknown default:
                return "iCloud returned an unknown account status."
            }
        } catch {
            return "iCloud is not available: \(error.localizedDescription)"
        }
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

        let storeURL = directory.appendingPathComponent("CloudRecovery.store")
        let schema = CadenceStore.schema
        let configuration = ModelConfiguration(schema: schema, url: storeURL,
                                               cloudKitDatabase: .private(containerID))
        let cloud: ModelContainer
        do {
            cloud = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            return Report(downloadedSessions: 0, changedRecords: 0,
                          liveSessionsBefore: before, liveSessionsAfter: before,
                          errors: ["Could not open the iCloud recovery store: \(error.localizedDescription)"])
        }

        progress("Contacting iCloud…")
        var lastCount = 0
        var quietTicks = 0
        var downloaded = 0
        // Up to five minutes. CloudKit imports in batches; stop after the count
        // has been stable for ~10 seconds once something has arrived.
        for tick in 0..<150 {
            if Task.isCancelled { break }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                break
            }
            let count = (try? ModelContext(cloud).fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
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
                          errors: ["iCloud did not return any workouts. Check that this device is signed into iCloud and that Cladiron still has iCloud access in Settings."])
        }

        progress("Merging \(downloaded) workouts into your local history…")
        do {
            let cloudContext = ModelContext(cloud)
            let archive = try NativeDatabaseExport.build(from: cloudContext)
            let changed = try NativeDatabaseExport.merge(archive, in: liveContext)
            try liveContext.save()
            let after = (try? liveContext.fetchCount(FetchDescriptor<WorkoutSession>())) ?? before
            return Report(downloadedSessions: downloaded, changedRecords: changed,
                          liveSessionsBefore: before, liveSessionsAfter: after, errors: [])
        } catch {
            return Report(downloadedSessions: downloaded, changedRecords: 0,
                          liveSessionsBefore: before, liveSessionsAfter: before,
                          errors: ["Downloaded data could not be merged: \(error.localizedDescription)"])
        }
    }
}
