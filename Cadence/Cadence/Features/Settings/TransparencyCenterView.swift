import SwiftUI
import CadenceCore
import CadenceFeatures

/// A plain-language inventory of automatic work and the controls available for
/// it. This is intentionally a settings destination: transient banners explain
/// what is happening now, while this screen explains why it happened and what
/// the user can edit, stop, retry, undo, or restore.
struct TransparencyCenterView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(ActiveWorkoutModel.self) private var active

    var body: some View {
        Form {
            Section("Right now") {
                statusRow(String(localized: "Apple Health"), systemImage: "heart.text.square",
                          value: model.healthSyncStatus.detailText)
                statusRow(String(localized: "Health restore"), systemImage: "arrow.down.heart",
                          value: model.healthRestoreStatus.detailText)
                statusRow(String(localized: "Watch"), systemImage: "applewatch",
                          value: model.watchSyncState.settingsText(lastSyncAt: model.lastWatchSyncAt))
                statusRow("iCloud", systemImage: "icloud",
                          value: model.isRestoringCloudKitHistory
                            ? AppModel.CloudKitImportStatus.updating.detailText
                            : (model.cloudKitImportStatus == .idle
                                ? model.cloudKitAccountAvailability.displayName
                                : model.cloudKitImportStatus.detailText))
                statusRow(String(localized: "Coach"), systemImage: "wand.and.stars",
                          value: model.coachRefreshInProgress
                            ? String(localized: "Updating coaching guidance…")
                            : String(localized: "No coach refresh running"))
                statusRow(String(localized: "Workout"), systemImage: "figure.strengthtraining.traditional",
                          value: active.isActive ? (active.isPaused ? String(localized: "Paused — user can resume or finish") : String(localized: "Active — user controls pause/finish")) : String(localized: "No active workout"))
            }

            Section("Automatic work") {
                explanationRow(
                    title: String(localized: "Apple Health import"),
                    detail: String(localized: "When Home opens and when you pull to refresh, Cladiron checks for new Watch/Health workouts and imports only records it has not already seen."),
                    control: String(localized: "You can see the current status above and repeat the check with pull-to-refresh. Imported records remain editable through History; auto-save back to Health is separately controlled below."))

                explanationRow(
                    title: String(localized: "Apple Health restore"),
                    detail: String(localized: "Restore re-reads Cladiron workouts from Apple Health, keeps newer local edits, and preserves partner sets that only exist in Cladiron."),
                    control: String(localized: "Run it again whenever Health finishes syncing to a new iPhone. A zero result can also mean Health read access is off in Settings."))

                explanationRow(
                    title: String(localized: "Coach refresh"),
                    detail: String(localized: "Home recomputes an ephemeral coach projection after relevant history, readiness, or preference changes. It does not save or replace a user-reviewed workout."),
                    control: String(localized: "Pull down on Home to rerun the refresh. Coach guidance never changes a workout automatically. Review and edit a Personalized or Custom Workout explicitly before starting or scheduling it."))

                explanationRow(
                    title: String(localized: "Watch projection"),
                    detail: String(localized: "The current plan and relevant settings are sent to the paired Watch so its execution surface can reflect the phone’s latest state."),
                    control: String(localized: "Edit the source plan on iPhone, use Sync to Watch Now to retry, and inspect the Watch status and error in Settings."))

                explanationRow(
                    title: String(localized: "Private iCloud mirror"),
                    detail: String(localized: "SwiftData and Apple’s private CloudKit mirror exchange local changes incrementally. Apple schedules the transfer; Cladiron does not operate a server or inspect the data."),
                    control: String(localized: "The app cannot stop an individual Apple-managed transfer. Use iCloud Details & Diagnostics for status, refresh, export, and legacy recovery; local history is never replaced by a failed recovery."))

                explanationRow(
                    title: String(localized: "Supporter prompt"),
                    detail: String(localized: "The optional contribution prompt is shown only at a natural Home break after the engagement gates are met."),
                    control: String(localized: "Choose Maybe later or Don’t ask again. The contribution unlocks nothing and does not change coaching or planning."))
            }

            Section("User controls") {
                Toggle("Auto-save workout summaries to Apple Health", isOn: Binding(
                    get: { settings.autoSaveHealth },
                    set: { settings.autoSaveHealth = $0 }))
                    .accessibilityIdentifier("transparency.autoSaveHealth")
                Text("When enabled, a completed workout may write its summary to Apple Health. The setting is off/on at your direction; detailed sets remain in Cladiron’s local/private-iCloud data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await model.restoreHealthBackups() }
                } label: {
                    if model.healthRestoreStatus.isInProgress {
                        HStack { ProgressView(); Text("Restoring from Apple Health…") }
                    } else {
                        Label("Restore from Apple Health", systemImage: "arrow.down.heart")
                    }
                }
                .disabled(model.healthRestoreStatus.isInProgress)
                .accessibilityIdentifier("settings.restoreHealth")
                NavigationLink {
                    CloudKitSyncDiagnosticsView()
                } label: {
                    Label("Open iCloud Details & Diagnostics", systemImage: "stethoscope")
                }
                NavigationLink {
                    BackupRestoreCenterView()
                } label: {
                    Label("Open Backup & Restore", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Drill down")
            } footer: {
                Text("Cladiron does not make hidden workout changes. Where a platform operation cannot be stopped in flight, this screen identifies the platform owner and gives the available retry, diagnostic, export, or recovery path.")
            }
        }
        .navigationTitle("Transparency & Control")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.transparency")
    }

    private func statusRow(_ title: String, systemImage: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func explanationRow(title: String, detail: String, control: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail)
            Text("Control: \(control)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
