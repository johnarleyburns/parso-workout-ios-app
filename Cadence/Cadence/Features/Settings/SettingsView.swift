import SwiftUI
import CadenceCore
import CadenceFeatures

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settingsObject
    @Environment(ContributionCoordinator.self) private var contributions

    @State private var healthStatus: HealthAuthorizationStatus = .notDetermined
    @State private var primingPresented = false

    var body: some View {
        @Bindable var settings = settingsObject
        Form {
            Section("Units & Records") {
                Picker("Weight unit", selection: $settings.unit) {
                    ForEach(MeasurementUnitPreference.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.unit")
                Picker("Distance unit", selection: $settings.distanceUnit) {
                    ForEach(DistanceUnitPreference.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.distanceUnit")
                Picker("PR rule", selection: $settings.prRule) {
                    ForEach(PRRule.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.prRule")
                Picker("1RM formula", selection: $settings.formula) {
                    ForEach(OneRepMaxFormula.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.formula")
            }

            Section {
                Button {
                    primingPresented = true
                } label: {
                    HStack {
                        Label("Apple Health", systemImage: "heart.text.square")
                        Spacer()
                        Text(statusText).foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.health.status")
                    }
                }
                .accessibilityIdentifier("settings.health.connect")

                Toggle("Auto-save to Apple Health", isOn: $settings.autoSaveHealth)
                    .accessibilityIdentifier("settings.autoSaveHealth")

                if let lastSync = model.lastHealthSync {
                    HStack {
                        Label("Last sync", systemImage: "clock.arrow.2.circlepath")
                        Spacer()
                        Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    HRMSettingsView()
                } label: {
                    Label("Heart-Rate Monitor", systemImage: "antenna.radiowaves.left.and.right")
                }
                .accessibilityIdentifier("settings.hrm")
            } header: {
                Text("Health & Sensors")
            } footer: {
                Text("Your health data stays on your device. Detailed sets stay local; only workout summaries are written to Apple Health.")
            }

            Section {
                HStack {
                    Label("Status", systemImage: "applewatch")
                    Spacer()
                    if model.watchSyncState.isInProgress {
                        ProgressView()
                    }
                    Text(model.watchSyncState.settingsText(lastSyncAt: model.lastWatchSyncAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("settings.watchSync.status")
                }

                HStack {
                    Label("Last synced", systemImage: "clock.arrow.2.circlepath")
                    Spacer()
                    Text(WatchSync.Status.lastSyncText(model.lastWatchSyncAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.watchSync.lastSynced")
                }

                if let error = model.lastWatchSyncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings.watchSync.error")
                }

                Button {
                    model.pushSettingsContext(force: true)
                } label: {
                    if model.watchSyncState.isInProgress {
                        HStack { ProgressView(); Text("Syncing to Watch...") }
                    } else {
                        Label("Sync to Watch Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(model.watchSyncState.isInProgress)
                .accessibilityIdentifier("settings.watchSync.force")
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("Sends units, interval defaults, workout sounds, and recent partners to the Watch app.")
            }

            Section {
                NavigationLink {
                    CardioIntensitySettingsView()
                } label: {
                    Label("Cardio Intensity", systemImage: "waveform.path.ecg")
                }
                .accessibilityIdentifier("settings.cardioIntensity")

                NavigationLink {
                    CoachResearchUpdatesView()
                } label: {
                    HStack {
                        Label("Coach Research Updates", systemImage: "book.closed")
                        Spacer()
                        if CoachKBBadge.hasUnseenUpdate(lastSeen: settings.lastSeenCoachKBVersion) {
                            Text("New")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(.green, in: Capsule())
                                .foregroundStyle(.white)
                                .accessibilityIdentifier("settings.coachUpdates.badge")
                        }
                    }
                }
                .accessibilityIdentifier("settings.coachUpdates")

                NavigationLink {
                    CoachMethodologyView()
                } label: {
                    Label("Coach Methodology", systemImage: "text.book.closed")
                }
                .accessibilityIdentifier("settings.coach.methodology")

                NavigationLink {
                    CoachSchedulePreferencesView()
                } label: {
                    Label("Coach & Plan", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings.coach.plan")

                NavigationLink {
                    CoachMethodologyView()
                } label: {
                    Label("Coach Insights & Methodology", systemImage: "lightbulb")
                }
                .accessibilityIdentifier("settings.coach.insights")
            } header: {
                Text("Coach")
            } footer: {
                Text("The coaching engine updates quarterly with new research. Everything else in Cladiron is free forever.")
            }

            Section("Exercises") {
                NavigationLink {
                    TemplatesView(onStart: { _ in })
                } label: {
                    Label("Saved Workouts", systemImage: "square.stack.3d.up")
                }
                .accessibilityIdentifier("settings.savedWorkouts")

                NavigationLink {
                    CustomExerciseListView()
                } label: {
                    Label("Custom Exercises", systemImage: "figure.strengthtraining.traditional")
                }
                .accessibilityIdentifier("settings.customExercises")

                NavigationLink {
                    ExcludedExercisesView()
                } label: {
                    Label("Excluded Exercises", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("settings.excludedExercises")
            }

            Section("Data") {
                NavigationLink {
                    ImportView()
                } label: { Label("Import Workout Log", systemImage: "square.and.arrow.down") }
                    .accessibilityIdentifier("settings.import")
                NavigationLink {
                    ExportView()
                } label: { Label("Backup & Restore", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("settings.export")
            }

            Section {
                NavigationLink {
                    TransparencyCenterView()
                } label: {
                    Label("Transparency & Control", systemImage: "eye")
                }
                .accessibilityIdentifier("settings.transparency")
            } footer: {
                Text("See what Cladiron is doing automatically, why it happened, and how to edit, stop, retry, undo, or restore it when supported.")
            }

            Section {
                Toggle("Workout sounds", isOn: $settings.workoutSounds)
                    .accessibilityIdentifier("settings.workoutSounds")
            } header: {
                Text("Sounds")
            } footer: {
                Text("Plays a bell at each transition — workout start, warm-up, work, cool-down and end — so you can start and stop without watching your phone. Boxing keeps its own round bell.")
            }

            Section {
                HStack {
                    Label("iCloud Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                    Spacer()
                    Text(model.cloudKitAccountAvailability.displayName)
                        .font(.caption)
                        .foregroundStyle(model.cloudKitAccountAvailability.canSync ? Color.secondary : Color.orange)
                        .accessibilityIdentifier("settings.sync.status")
                }

                NavigationLink {
                    CloudKitSyncDiagnosticsView()
                } label: {
                    Label("iCloud Details & Diagnostics", systemImage: "stethoscope")
                }
                .accessibilityIdentifier("settings.sync.diagnostics")
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text("Your workout data uses Apple’s private iCloud database. Sync is automatic and incremental; Apple schedules imports and exports. Detailed storage and recovery information is in iCloud Details & Diagnostics.")
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                .accessibilityIdentifier("settings.about")
            }

            Section {
                NavigationLink {
                    ContributionSupportView(store: contributions.store)
                } label: {
                    Label(contributions.store.isSupporter ? "Supporter — Thank You" : "Support Cladiron",
                          systemImage: contributions.store.isSupporter ? "heart.fill" : "heart")
                        .foregroundStyle(contributions.store.isSupporter ? Color.pink : Color.accentColor)
                }
                .accessibilityIdentifier("settings.support")
            } footer: {
                Text("Cladiron is open source and ad-free. A one-time tip is an optional way to support development — never required.")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $primingPresented) {
            HealthPrimingView { status in healthStatus = status }
        }
    }

    private var statusText: String {
        switch healthStatus {
        case .authorized: return "Connected"
        case .denied: return "Denied"
        case .unavailable: return "Unavailable"
        case .notDetermined: return "Not connected"
        }
    }
}

/// Cardio inputs are explicit and editable. A user-entered maximum outranks an
/// age estimate, while resting HR is read on-device from HealthKit and shown with
/// its source so the app never silently invents a threshold.
private struct CardioIntensitySettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var maximumHRText = ""
    @State private var restingHR: Double?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Current profile") {
                LabeledContent("Resting HR", value: restingHR.map { "\(Int($0.rounded())) bpm" } ?? "Unavailable")
                LabeledContent("Maximum HR", value: currentMaximumText)
                Text("Heart-rate reserve is used when both values are valid. Otherwise the workout is shown as unclassified rather than receiving made-up intensity credit.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Maximum heart rate") {
                TextField("Optional bpm", text: $maximumHRText)
                    .keyboardType(.numberPad)
                    .onChange(of: maximumHRText) { _, value in
                        let number = Double(value.filter { $0.isNumber })
                        settings.cardioMaximumHROverride = number.flatMap { (100...240).contains($0) ? $0 : nil }
                    }
                if settings.cardioMaximumHROverride != nil {
                    Button("Use age estimate instead", role: .destructive) {
                        maximumHRText = ""
                        settings.cardioMaximumHROverride = nil
                    }
                }
                Text("Leave blank to use Tanaka’s age estimate when your age is set. A lab or field-tested value is preferable to an estimate.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("What the numbers mean") {
                NavigationLink {
                    CardioIntensityScienceView()
                } label: {
                    Label("Cardio science & credit", systemImage: "book.closed")
                }
                .accessibilityIdentifier("settings.cardioIntensity.science")
            }
        }
        .navigationTitle("Cardio Intensity")
        .task {
            maximumHRText = settings.cardioMaximumHROverride.map { String(Int($0)) } ?? ""
            let samples = await model.health.passiveReadinessSamples(days: 30)
            let values = samples.compactMap(\.restingHR).filter { $0 > 25 && $0 < 160 }.sorted()
            restingHR = values.isEmpty ? nil : values[values.count / 2]
        }
    }

    private var currentMaximumText: String {
        if let value = settings.cardioMaximumHROverride { return "\(Int(value.rounded())) bpm · entered" }
        if let age = settings.userAge { return "\(Int(HeartRateMaximum.tanaka(age: age).rounded())) bpm · age-estimated" }
        return "Unavailable"
    }
}

private struct CardioIntensityScienceView: View {
    var body: some View {
        List {
            Section("Intensity") {
                Text("Cladiron classifies each timestamped heart-rate interval independently. Heart-rate reserve is (heart rate − resting heart rate) ÷ (maximum heart rate − resting heart rate), an estimate of relative effort rather than a whole-workout average.")
                Text("Below 40% reserve is below moderate; 40–<60% is moderate; 60% or more is vigorous for guideline credit. Below-moderate minutes receive zero credit, moderate minutes count once, and vigorous minutes count twice.")
            }
            Section("Separate measurements") {
                Text("Actual exercise minutes, guideline credit, training-zone time, and standardized MET-minutes are separate axes. MET-minutes describe population-level activity dose and do not replace guideline credit.")
            }
            Section("Sources") {
                ForEach(["swainLeutholtz1997HRR", "tanakaMaxHR2001", "piercy2018PhysicalActivityGuidelines", "compendium2024AdultPhysicalActivities"], id: \.self) { id in
                    if let citation = CitationRegistry.citation(forId: id) {
                        CitationLink(citation: citation, compact: true)
                    }
                }
            }
        }
        .navigationTitle("Cardio Science")
    }
}
