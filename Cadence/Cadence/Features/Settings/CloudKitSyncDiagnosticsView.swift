import SwiftUI
import SwiftData
import CloudKit
import CadenceCore

/// A read-only view of the current Cladiron store and the private CloudKit
/// container that mirrors it. Normal sync is managed by Apple's
/// SwiftData/CloudKit mirror, so this screen reports state and never forces or
/// rewrites it.
struct CloudKitSyncDiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.cadenceModelContainer) private var container

    @State private var snapshot: CloudKitDiagnosticsSnapshot?
    @State private var isRefreshing = false
    @State private var storageUsage = StorageUsageSnapshot()

    var body: some View {
        Form {
            Section("This iPhone") {
                if let snapshot {
                    diagnosticRow(String(localized: "Workout records"), value: "\(snapshot.localWorkoutCount)")
                    diagnosticRow(String(localized: "Newest local workout"), value: dateText(snapshot.localLatestWorkoutDate))
                } else {
                    HStack {
                        ProgressView()
                        Text("Reading local history…")
                    }
                }
            }

            Section("iCloud") {
                if let snapshot {
                    diagnosticRow(String(localized: "Account"), value: snapshot.account.displayName)
                    diagnosticRow(String(localized: "Container"), value: CadenceStore.splitCloudKitContainerID)
                    diagnosticRow(String(localized: "Sync mode"), value: String(localized: "Automatic · incremental"))
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

            Section("Local store") {
                diagnosticRow(String(localized: "Cladiron data"), value: storageUsage.appDataText)
                diagnosticRow(String(localized: "Workout database"), value: storageUsage.workoutStoreText)
                diagnosticRow(String(localized: "Free iPhone storage"), value: storageUsage.deviceFreeText)
                diagnosticRow("iCloud storage used", value: String(localized: "Not exposed by Apple"))
            }

            Section {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        HStack { ProgressView(); Text("Checking iCloud…") }
                    } else {
                        Label("Refresh Status", systemImage: "arrow.clockwise.icloud")
                    }
                }
                .disabled(isRefreshing)
                .accessibilityIdentifier("settings.sync.diagnostics.refresh")
            } header: {
                Text("Actions")
            } footer: {
                Text("Normal sync is managed by Apple’s SwiftData/CloudKit mirror and is incremental; this screen cannot force it, and it never deletes or overwrites local history.")
            }
        }
        .navigationTitle("iCloud Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
            guard !Task.isCancelled else { return }
            let measurementContainer = container
            storageUsage = await Task.detached(priority: .utility) {
                StorageUsageSnapshot.measure(container: measurementContainer)
            }.value
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        guard let container else {
            isRefreshing = false
            return
        }
        model.refreshCloudKitAccountStatus()
        snapshot = await CloudKitDiagnosticsService(container: container).inspect()
        isRefreshing = false
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
        guard let date else { return String(localized: "None") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

@MainActor
struct CloudKitDiagnosticsService {
    let container: ModelContainer
    var cloud: CKContainer = CKContainer(identifier: CadenceStore.splitCloudKitContainerID)

    func inspect() async -> CloudKitDiagnosticsSnapshot {
        let local = localHistory()
        do {
            let status = try await cloud.accountStatus()
            return CloudKitDiagnosticsSnapshot(
                localWorkoutCount: local.count,
                localLatestWorkoutDate: local.latest,
                account: CloudKitAccountGate.availability(for: status.rawValue))
        } catch {
            return CloudKitDiagnosticsSnapshot(
                localWorkoutCount: local.count,
                localLatestWorkoutDate: local.latest,
                account: .temporarilyUnavailable,
                remoteError: String(localized: "Could not check iCloud: \(error.localizedDescription)"))
        }
    }

    private func localHistory() -> (count: Int, latest: Date?) {
        let context = ModelContext(container)
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

struct CloudKitDiagnosticsSnapshot: Equatable {
    let localWorkoutCount: Int
    let localLatestWorkoutDate: Date?
    let account: CloudKitAccountAvailability
    var remoteError: String?
}
