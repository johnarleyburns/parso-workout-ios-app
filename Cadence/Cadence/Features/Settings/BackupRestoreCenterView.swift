import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// The dedicated H6 Backup & Restore center. It explains each backup path,
/// shows durable HealthKit queue progress, and keeps destructive/ambiguous
/// operations behind the existing explicit controls.
struct BackupRestoreCenterView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.cadenceModelContainer) private var container

    @State private var localCounts = LocalBackupCounts()
    @State private var isRefreshing = false

    var body: some View {
        Form {
            Section("At a glance") {
                let status = BackupCenterPresenter.status(
                    autoSaveHealth: settings.autoSaveHealth,
                    pendingHealthItems: model.healthBackup.lastReport.remaining,
                    lastHealthError: model.healthBackup.lastReport.lastError)
                statusRow("Apple Health", systemImage: "heart.text.square",
                          title: status.healthTitle, detail: status.healthDetail)
                statusRow("Cladiron archive", systemImage: "externaldrive",
                          title: "Ready to export",
                          detail: "\(localCounts.sessions) strength · \(localCounts.cardio) cardio · \(localCounts.assessments) fitness tests")
                statusRow("Restore", systemImage: "arrow.down.heart",
                          title: restoreTitle, detail: restoreDetail)
            }

            if !settings.autoSaveHealth {
                Section {
                    Label("Apple Health backup is off", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
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

            Section("Full Cladiron archive") {
                Text("JSON is the lossless backup for a new device. FIT is for cardio/activity exchange; it intentionally does not contain strength sets or preferences.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    ExportView()
                } label: {
                    Label("Export or restore JSON, FIT, or CSV", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("backupCenter.openExport")
            }

            Section {
                NavigationLink {
                    CloudKitSyncDiagnosticsView()
                } label: {
                    Label("iCloud Details & Diagnostics", systemImage: "stethoscope")
                }
                Text("CloudKit transfers are controlled by Apple. This screen shows their state but cannot interrupt an in-flight platform transfer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.backupCenter")
        .task { await reload() }
    }

    private var restoreTitle: String {
        switch model.healthRestoreStatus {
        case .idle: return "Not run this launch"
        case .restoring: return "In progress"
        case .completed: return "Complete"
        case .failed: return "Needs attention"
        }
    }

    private var restoreDetail: String {
        switch model.healthRestoreStatus {
        case .idle: return "Restore is safe to repeat after Health finishes syncing."
        case .restoring: return "Reading Cladiron-authored objects from Apple Health."
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
