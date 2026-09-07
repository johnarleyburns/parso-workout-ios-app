import SwiftUI
import SwiftData
import CloudKit
import CadenceCore

/// A read-only view of the local store plus a guarded recovery path for the
/// legacy, app-managed iCloud export blob. The current store is mirrored by
/// SwiftData/Core Data, so this cannot force that managed mirror to run; it can
/// still recover a blob created by the older backup implementation if it is
/// still present in the user's private database.
struct CloudKitSyncDiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.cadenceModelContainer) private var container

    @State private var snapshot: CloudKitRecoverySnapshot?
    @State private var isRefreshing = false
    @State private var isRecovering = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("This iPhone") {
                if let snapshot {
                    diagnosticRow("Workout records", value: "\(snapshot.localWorkoutCount)")
                    diagnosticRow("Newest local workout", value: dateText(snapshot.localLatestWorkoutDate))
                } else {
                    HStack {
                        ProgressView()
                        Text("Reading local history…")
                    }
                }
            }

            Section("iCloud") {
                if let snapshot {
                    diagnosticRow("Account", value: snapshot.account.displayName)
                    diagnosticRow("Container", value: CadenceStore.cloudKitContainerID)
                    diagnosticRow("Legacy backup", value: snapshot.legacyBackupFound ? "Found" : "Not found")
                    if snapshot.legacyBackupFound {
                        diagnosticRow("Backup date", value: dateText(snapshot.legacyBackupDate))
                        diagnosticRow("Backup workouts", value: snapshot.legacyBackupSessionCount.map(String.init) ?? "Unknown")
                    }
                    if let remoteError = snapshot.remoteError {
                        Text(remoteError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("settings.sync.diagnostics.error")
                    }
                } else {
                    HStack {
                        ProgressView()
                        Text("Checking iCloud…")
                    }
                }
            }

            Section {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        HStack { ProgressView(); Text("Checking iCloud…") }
                    } else {
                        Label("Refresh iCloud Status", systemImage: "arrow.clockwise.icloud")
                    }
                }
                .disabled(isRefreshing || isRecovering)
                .accessibilityIdentifier("settings.sync.diagnostics.refresh")

                Button {
                    Task { await recover() }
                } label: {
                    if isRecovering {
                        HStack { ProgressView(); Text("Recovering…") }
                    } else {
                        Label("Attempt Legacy Backup Recovery", systemImage: "arrow.down.icloud")
                    }
                }
                .disabled(isRefreshing || isRecovering || !(snapshot?.legacyBackupFound ?? false))
                .accessibilityIdentifier("settings.sync.diagnostics.recover")

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.sync.diagnostics.result")
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("Recovery only merges records from the older Cladiron iCloud backup, if one exists. It never deletes or overwrites local history. Refresh checks status; it cannot directly force Apple's managed SwiftData sync.")
            }
        }
        .navigationTitle("iCloud Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        message = nil
        guard let container else {
            message = "The local data store is unavailable."
            isRefreshing = false
            return
        }
        model.refreshCloudKitAccountStatus()
        snapshot = await CloudKitRecoveryService(container: container).inspect()
        isRefreshing = false
    }

    private func recover() async {
        guard !isRecovering else { return }
        isRecovering = true
        message = nil
        guard let container else {
            message = "The local data store is unavailable."
            isRecovering = false
            return
        }
        do {
            let added = try await CloudKitRecoveryService(container: container).recoverLegacyBackup()
            message = added == 0
                ? "Recovery completed; no new workouts were needed."
                : "Recovery merged \(added) workout\(added == 1 ? "" : "s")."
            snapshot = await CloudKitRecoveryService(container: container).inspect()
        } catch {
            message = "Recovery failed: \(error.localizedDescription)"
        }
        isRecovering = false
    }

    private func diagnosticRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "None" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

@MainActor
final class CloudKitRecoveryService {
    private static let legacyRecordName = "latest"
    private static let legacyAssetKey = "payload"
    private static let legacyCreatedAtKey = "createdAt"
    private static let legacySessionCountKey = "sessionCount"

    private let modelContainer: ModelContainer
    private let cloud: CKContainer

    init(container: ModelContainer,
         cloud: CKContainer = CKContainer(identifier: CadenceStore.cloudKitContainerID)) {
        self.modelContainer = container
        self.cloud = cloud
    }

    func inspect() async -> CloudKitRecoverySnapshot {
        let local = localHistory()
        let account: CloudKitAccountAvailability
        do {
            let status = try await cloud.accountStatus()
            account = CloudKitAccountGate.availability(for: status.rawValue)
        } catch {
            return CloudKitRecoverySnapshot(localWorkoutCount: local.count,
                                             localLatestWorkoutDate: local.latest,
                                             account: .temporarilyUnavailable,
                                             remoteError: "Could not check iCloud: \(error.localizedDescription)")
        }

        guard account == .available else {
            return CloudKitRecoverySnapshot(localWorkoutCount: local.count,
                                             localLatestWorkoutDate: local.latest,
                                             account: account)
        }

        do {
            let record = try await cloud.privateCloudDatabase.record(
                for: CKRecord.ID(recordName: Self.legacyRecordName))
            return CloudKitRecoverySnapshot(
                localWorkoutCount: local.count,
                localLatestWorkoutDate: local.latest,
                account: account,
                legacyBackupFound: true,
                legacyBackupDate: record[Self.legacyCreatedAtKey] as? Date,
                legacyBackupSessionCount: (record[Self.legacySessionCountKey] as? Int)
                    ?? (record[Self.legacySessionCountKey] as? NSNumber)?.intValue)
        } catch let error as CKError where error.code == .unknownItem {
            return CloudKitRecoverySnapshot(localWorkoutCount: local.count,
                                             localLatestWorkoutDate: local.latest,
                                             account: account)
        } catch {
            return CloudKitRecoverySnapshot(localWorkoutCount: local.count,
                                             localLatestWorkoutDate: local.latest,
                                             account: account,
                                             remoteError: "Could not inspect the legacy backup: \(error.localizedDescription)")
        }
    }

    /// Downloads and merges the old single-record export backup. This is
    /// intentionally merge-only: `WorkoutRepository.merge` deduplicates stable
    /// IDs and does not remove anything from the current store.
    func recoverLegacyBackup() async throws -> Int {
        let status = try await cloud.accountStatus()
        guard CloudKitAccountGate.availability(for: status.rawValue) == .available else {
            throw CloudKitRecoveryError.iCloudUnavailable
        }

        let record = try await cloud.privateCloudDatabase.record(
            for: CKRecord.ID(recordName: Self.legacyRecordName))
        guard let asset = record[Self.legacyAssetKey] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw CloudKitRecoveryError.backupPayloadMissing
        }
        let container = modelContainer
        return try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: fileURL)
            let export = try DataExport.decodeAny(data)
            let context = ModelContext(container)
            return try WorkoutRepository.merge(export, in: context)
        }.value
    }

    private func localHistory() -> (count: Int, latest: Date?) {
        let context = ModelContext(modelContainer)
        let sessionPredicate = #Predicate<WorkoutSession> { $0.deletedAt == nil }
        let cardioPredicate = #Predicate<CardioWorkout> { $0.deletedAt == nil }
        let sessionCount = (try? context.fetchCount(FetchDescriptor<WorkoutSession>(
            predicate: sessionPredicate))) ?? 0
        let cardioCount = (try? context.fetchCount(FetchDescriptor<CardioWorkout>(
            predicate: cardioPredicate))) ?? 0
        var sessionLatest = FetchDescriptor<WorkoutSession>(
            predicate: sessionPredicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        sessionLatest.fetchLimit = 1
        var cardioLatest = FetchDescriptor<CardioWorkout>(
            predicate: cardioPredicate,
            sortBy: [SortDescriptor(\.start, order: .reverse)])
        cardioLatest.fetchLimit = 1
        let sessions = (try? context.fetch(sessionLatest)) ?? []
        let cardio = (try? context.fetch(cardioLatest)) ?? []
        return (sessionCount + cardioCount,
                [sessions.first?.date, cardio.first?.start].compactMap { $0 }.max())
    }
}

struct CloudKitRecoverySnapshot: Equatable {
    let localWorkoutCount: Int
    let localLatestWorkoutDate: Date?
    let account: CloudKitAccountAvailability
    var legacyBackupFound = false
    var legacyBackupDate: Date?
    var legacyBackupSessionCount: Int?
    var remoteError: String?
}

enum CloudKitRecoveryError: LocalizedError {
    case iCloudUnavailable
    case backupPayloadMissing

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is not currently available to Cladiron."
        case .backupPayloadMissing:
            return "The legacy iCloud backup record has no recoverable payload."
        }
    }
}
