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
                statusRow("Apple Health", systemImage: "heart.text.square",
                          value: model.healthSyncStatus.detailText)
                statusRow("Watch", systemImage: "applewatch",
                          value: model.watchSyncState.settingsText(lastSyncAt: model.lastWatchSyncAt))
                statusRow("iCloud", systemImage: "icloud",
                          value: model.isRestoringCloudKitHistory
                            ? AppModel.CloudKitImportStatus.updating.detailText
                            : (model.cloudKitImportStatus == .idle
                                ? model.cloudKitAccountAvailability.displayName
                                : model.cloudKitImportStatus.detailText))
                statusRow("Coach", systemImage: "wand.and.stars",
                          value: model.coachRefreshInProgress
                            ? "Updating coaching guidance…"
                            : "No coach refresh running")
                statusRow("Workout", systemImage: "figure.strengthtraining.traditional",
                          value: active.isActive ? (active.isPaused ? "Paused — user can resume or finish" : "Active — user controls pause/finish") : "No active workout")
            }

            Section("Automatic work") {
                explanationRow(
                    title: "Apple Health import",
                    detail: "When Home opens and when you pull to refresh, Cladiron checks for new Watch/Health workouts and imports only records it has not already seen.",
                    control: "You can see the current status above and repeat the check with pull-to-refresh. Imported records remain editable through History; auto-save back to Health is separately controlled below.")

                explanationRow(
                    title: "Coach refresh",
                    detail: "Home recomputes an ephemeral coach projection after relevant history, readiness, or preference changes. It does not save or replace a user-reviewed workout.",
                    control: "Pull down on Home to rerun the refresh. Coach guidance never changes a workout automatically. Review and edit a Personalized or Custom Workout explicitly before starting or scheduling it.")

                explanationRow(
                    title: "Watch projection",
                    detail: "The current plan and relevant settings are sent to the paired Watch so its execution surface can reflect the phone’s latest state.",
                    control: "Edit the source plan on iPhone, use Sync to Watch Now to retry, and inspect the Watch status and error in Settings.")

                explanationRow(
                    title: "Private iCloud mirror",
                    detail: "SwiftData and Apple’s private CloudKit mirror exchange local changes incrementally. Apple schedules the transfer; Cladiron does not operate a server or inspect the data.",
                    control: "The app cannot stop an individual Apple-managed transfer. Use iCloud Details & Diagnostics for status, refresh, export, and legacy recovery; local history is never replaced by a failed recovery.")

                explanationRow(
                    title: "Supporter prompt",
                    detail: "The optional contribution prompt is shown only at a natural Home break after the engagement gates are met.",
                    control: "Choose Maybe later or Don’t ask again. The contribution unlocks nothing and does not change coaching or planning.")
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
                NavigationLink {
                    CloudKitSyncDiagnosticsView()
                } label: {
                    Label("Open iCloud Details & Diagnostics", systemImage: "stethoscope")
                }
                NavigationLink {
                    ExportView()
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
