import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Coverage note plus the user-triggered "Reload cardio measurements from Apple Health" action
/// for a completed strength session. Existing data is only replaced after validation.
struct HeartRateRepairSection: View {
    let session: WorkoutSession
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel
    @Environment(ActiveWorkoutModel.self) private var active
    @State private var isLoading = false
    @State private var message: String?
    @State private var choices: [HealthWorkoutCandidate] = []
    @State private var pendingConfirmation: HealthWorkoutCandidate?
    @State private var showConfirm = false
    @State private var preview: HeartRateRepairPreview?
    @State private var previewChoice: HealthWorkoutCandidate?

    var body: some View {
        if active.heartRatePendingSessionID == session.id {
            VStack(alignment: .leading, spacing: 8) {
                Text("Waiting for cardio measurements. They are kept on this device and have not been saved yet.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Retry saving cardio measurements") {
                    Task {
                        let profile = await cardioIntensityProfile(model: appModel, settings: settings)
                        if active.finalizeHeartRate(profile: profile, sessionID: session.id) {
                            announce(String(localized: "Cardio measurements saved."))
                            NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
                        } else {
                            announce(String(localized: "Still couldn't save cardio measurements. Try again."))
                        }
                    }
                }
                .accessibilityIdentifier("summary.hrRetry")
                if let message { Text(message).font(.footnote) }
            }
        } else if session.endedAt != nil, HeartRateRepair.isRepairable(session) || session.hrBackup != nil {
            VStack(alignment: .leading, spacing: 8) {
                if HeartRateRepair.isRepairable(session) {
                    Text("Heart-rate coverage was incomplete, so part of this workout is unclassified. That reflects missing measurements, not low intensity.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Heart-rate coverage was incomplete for this workout"))
                    Button { Task { await repair() } } label: {
                        Text("Reload cardio measurements from Apple Health")
                    }
                    .disabled(isLoading)
                    .accessibilityHint(String(localized: "Looks for the matching Apple Health workout and imports its heart-rate samples. Nothing changes unless valid data is found."))
                }
                if isLoading {
                    ProgressView("Loading cardio measurements from Apple Health…")
                }
                if session.hrBackup != nil {
                    Button("Restore previous measurements") {
                        if HeartRateRepair.restorePrevious(session, save: { try modelContext.save() }) {
                            announce(String(localized: "Previous measurements restored."))
                            NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
                        }
                    }
                    .accessibilityHint(String(localized: "Undoes the last Apple Health reload for this workout."))
                }
                if let message { Text(message).font(.footnote).accessibilityIdentifier("summary.hrRepair.message") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: .init(get: { !choices.isEmpty }, set: { if !$0 { choices = [] } })) { selectionSheet }
            .confirmationDialog("Apply these measurements?", isPresented: .init(get: { preview != nil }, set: { if !$0 { preview = nil } }),
                                titleVisibility: .visible, presenting: preview) { p in
                Button("Apply") {
                    let chosen = previewChoice
                    preview = nil
                    Task { await repair(chosen: chosen, confirm: false, confirmed: true, legacy: p.isLegacyFallback) }
                }
                Button("Keep existing", role: .cancel) {}
            } message: { p in
                Text("\(p.sourceName): \(p.sampleCount) readings between \(p.sessionStart.formatted(date: .omitted, time: .shortened)) and \(p.sessionEnd.formatted(date: .omitted, time: .shortened)). Classified minutes: \(p.beforeClassifiedMinutes) now, \(p.afterClassifiedMinutes) after. You can restore the previous measurements afterward.")
            }
            .confirmationDialog("Replace existing measurements?", isPresented: $showConfirm) {
                Button("Replace") { if let c = pendingConfirmation { Task { await repair(chosen: c, confirm: true) } } }
                Button("Keep existing", role: .cancel) {}
            } message: {
                Text("Apple Health covers no more of this workout than what is already saved.")
            }
        }
    }

    private var selectionSheet: some View {
        NavigationStack {
            List(choices) { candidate in
                Button {
                    choices = []
                    Task { await repair(chosen: candidate) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(candidate.start.formatted(date: .abbreviated, time: .shortened))
                        Text("\(Int((candidate.duration / 60).rounded())) min · \(candidate.sourceName)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Choose a workout")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choices = [] } } }
        }
    }

    private func announce(_ text: String) {
        message = text
        AccessibilityNotification.Announcement(text).post()
    }

    private func repair(chosen: HealthWorkoutCandidate? = nil, confirm: Bool = false,
                        confirmed: Bool = false, legacy: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        let profile = CardioIntensityProfile.resolved(userEnteredMaximumHR: settings.cardioMaximumHROverride,
                                                      age: settings.userAge)
        let outcome = await HeartRateRepair.run(session: session, source: HealthKitHeartRateSource(),
                                                profile: profile, chosen: chosen, confirmReplacement: confirm,
                                                confirmed: confirmed, allowLegacyFallback: true,
                                                save: { try modelContext.save() })
        switch outcome {
        case .noMatch: announce(String(localized: "No matching Apple Health workout was found."))
        case .noHeartRateSamples: announce(String(localized: "Apple Health has no heart-rate samples for this workout."))
        case .accessError: announce(String(localized: "Couldn't read Apple Health. Check Health access in Settings and try again."))
        case .preview(let p):
            previewChoice = chosen
            preview = p
            AccessibilityNotification.Announcement(String(localized: "Review the proposed cardio measurements.")).post()
        case .needsSelection(let list): choices = list
        case .needsReplacementConfirmation:
            pendingConfirmation = chosen
            showConfirm = chosen != nil
            if chosen == nil { announce(String(localized: "Apple Health doesn't cover more of this workout than what is saved, so nothing was changed.")) }
        case .repaired(let classified, let total):
            announce(String(localized: "Cardio measurements updated: \(classified) of \(total) minutes classified."))
            NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
        }
    }
}
