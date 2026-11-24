import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// The dedicated H6 Backup & Restore center. It explains each backup path,
/// shows durable HealthKit queue progress, and keeps destructive/ambiguous
/// operations behind the existing explicit controls.
struct BackupRestoreCenterView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.cadenceModelContainer) private var container

    @State private var localCounts = LocalBackupCounts()
    @State private var isRefreshing = false
    @State private var recoveringPreviousData = false
    @State private var recoveryMessage: String?

    var body: some View {
        Form {
            Section("At a glance") {
                let status = BackupCenterPresenter.status(
                    autoSaveHealth: settings.autoSaveHealth,
                    pendingHealthItems: model.healthBackup.lastReport.remaining,
                    lastHealthError: model.healthBackup.lastReport.lastError)
                statusRow(String(localized: "Apple Health"), systemImage: "heart.text.square",
                          title: status.healthTitle, detail: status.healthDetail)
                statusRow(String(localized: "Cladiron archive"), systemImage: "externaldrive",
                          title: String(localized: "Ready to export"),
                          detail: String(localized: "\(localCounts.sessions) strength · \(localCounts.cardio) cardio · \(localCounts.assessments) fitness tests"))
                statusRow(String(localized: "Restore"), systemImage: "arrow.down.heart",
                          title: restoreTitle, detail: restoreDetail)
            }

            if !settings.autoSaveHealth {
                Section {
                    Label("Apple Health backup is off", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(CadenceTheme.attention)
                    Text("Your Cladiron history is still available in the app and in the full JSON archive. Turn this on if you want Cladiron-authored workouts copied into Apple Health.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Apple Health") {
                Text("Apple Health stores a private summary of your workouts and supported fitness tests. Detailed partner sets, readiness entries, plan snapshots, and imported-workout notes stay in Cladiron’s full archive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    Task { _ = await model.healthBackup.drain(); await reload() }
                } label: {
                    Label("Retry pending Health backups", systemImage: "arrow.clockwise.heart")
                }
                .disabled(model.healthBackup.lastReport.remaining == 0)
                .accessibilityIdentifier("backupCenter.retryHealth")

                Button {
                    Task { await model.restoreHealthBackups(); await reload() }
                } label: {
                    if model.healthRestoreStatus.isInProgress {
                        HStack { ProgressView(); Text("Restoring from Apple Health…") }
                    } else {
                        Label("Restore from Apple Health", systemImage: "arrow.down.heart")
                    }
                }
                .disabled(model.healthRestoreStatus.isInProgress)
                .accessibilityIdentifier("backupCenter.restoreHealth")
            }

            Section("Previous local data") {
                Text("If workouts disappeared after an update, Cladiron can merge them from a previous on-device store. The current store is kept. This can also restore workouts that were permanently deleted before the update.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await recoverPreviousData() }
                } label: {
                    if recoveringPreviousData {
                        HStack { ProgressView(); Text("Scanning previous stores…") }
                    } else {
                        Label("Recover Previous Data", systemImage: "clock.arrow.circlepath")
                    }
                }
                .disabled(recoveringPreviousData || container == nil)
                .accessibilityIdentifier("backupCenter.recoverPrevious")
                if let recoveryMessage {
                    Text(recoveryMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("backupCenter.recoveryResult")
                }
            }

            Section("Full Cladiron archive") {
                Text("JSON is the lossless backup for a new device; export it from Progress › My Workouts. FIT is for cardio/activity exchange; it intentionally does not contain strength sets or preferences.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    ExportView(mode: .restoreOnly)
                } label: {
                    Label("Restore or Import", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("backupCenter.openRestore")
            }

            Section {
                Text("Your history is stored only on this device. Cladiron does not upload it to a server. Keep the JSON archive somewhere safe so you can restore it on a new device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("backupCenter.localOnly")
            }
        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.backupCenter")
        .task { await reload() }
    }

    private var restoreTitle: String {
        switch model.healthRestoreStatus {
        case .idle: return String(localized: "Not run this launch")
        case .restoring: return String(localized: "In progress")
        case .completed: return String(localized: "Complete")
        case .failed: return String(localized: "Needs attention")
        }
    }

    private var restoreDetail: String {
        switch model.healthRestoreStatus {
        case .idle: return String(localized: "Restore is safe to repeat after Health finishes syncing.")
        case .restoring: return String(localized: "Reading Cladiron-authored objects from Apple Health.")
        case .completed(_, let report):
            return BackupCenterPresenter.restoreSummary(inserted: report.inserted,
                                                        replaced: report.replaced,
                                                        skipped: report.skipped)
        case .failed(let message): return message
        }
    }

    private func statusRow(_ title: String, systemImage: String,
                           title value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func recoverPreviousData() async {
        guard let container, !recoveringPreviousData else { return }
        guard container.configurations.contains(where: { !$0.isStoredInMemoryOnly }) else {
            recoveryMessage = String(localized: "Cladiron is using a temporary store. Restart the app before recovering previous data.")
            return
        }
        recoveringPreviousData = true
        recoveryMessage = nil
        let report = await Task.detached(priority: .userInitiated) {
            StoreRecovery.recover(into: container)
        }.value
        recoveringPreviousData = false
        if report.errors.isEmpty {
            recoveryMessage = String(localized: "Merged \(report.changedRecords) records. \(report.currentSessionsAfter) workouts are now in the live store.")
        } else {
            recoveryMessage = String(localized: "Merged \(report.changedRecords) records; \(report.errors.count) previous store(s) could not be read. \(report.currentSessionsAfter) workouts are now in the live store.")
        }
        await reload()
    }

    private func reload() async {
        guard let container, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let context = ModelContext(container)
        do {
            localCounts = LocalBackupCounts(
                sessions: try context.fetchCount(FetchDescriptor<WorkoutSession>()),
                cardio: try context.fetchCount(FetchDescriptor<CardioWorkout>()),
                assessments: try context.fetchCount(FetchDescriptor<Assessment>()))
        } catch {
            localCounts = .init()
        }
    }
}

private struct LocalBackupCounts: Equatable {
    var sessions = 0
    var cardio = 0
    var assessments = 0
}
