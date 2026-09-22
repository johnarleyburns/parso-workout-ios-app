import SwiftUI
import CadenceCore
import CadenceFeatures

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settingsObject
    @Environment(ContributionCoordinator.self) private var contributions

    @State private var healthStatus: HealthAuthorizationStatus = .notDetermined
    @State private var primingPresented = false
    @State private var workoutPreferencesPresented = false

    var body: some View {
        @Bindable var settings = settingsObject
        Form {
            Section("Workout Preferences") {
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
                Button { workoutPreferencesPresented = true } label: {
                    Label("Workout flow & defaults", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("settings.workoutPreferences")
                Toggle("Workout sounds", isOn: $settings.workoutSounds)
                    .accessibilityIdentifier("settings.workoutSounds")
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
                Text("Watch Sync")
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
                    SettingsCoachInsightsView()
                } label: {
                    Label("Coach Insights", systemImage: "lightbulb")
                }
                .accessibilityIdentifier("settings.coach.insights")

                NavigationLink {
                    CoachAboutView()
                } label: {
                    Label("About the Coach", systemImage: "person.fill.questionmark")
                }
                .accessibilityIdentifier("settings.coach.about")
            } header: {
                Text("Coach, Science & Rationale")
            } footer: {
                Text("The coaching engine updates quarterly with new research. Everything else in Cladiron is free forever.")
            }

            Section("Exercises & Exclusions") {
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

            Section("Data & Backup") {
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
                Text("CloudKit Sync")
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

                NavigationLink {
                    ContributionSupportView(store: contributions.store)
                } label: {
                    Label(contributions.store.isSupporter ? "Supporter — Thank You" : "Support Cladiron",
                          systemImage: contributions.store.isSupporter ? "heart.fill" : "heart")
                        .foregroundStyle(contributions.store.isSupporter ? Color.pink : Color.accentColor)
                }
                .accessibilityIdentifier("settings.support")
            } header: {
                Text("Support & About")
            } footer: {
                Text("Cladiron is open source and ad-free. A one-time tip is an optional way to support development — never required.")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $primingPresented) {
            HealthPrimingView { status in healthStatus = status }
        }
        .sheet(isPresented: $workoutPreferencesPresented) {
            WorkoutSettingsSheet(warmupMinutes: $settings.warmupMinutes,
                                 cooldownMinutes: $settings.cooldownMinutes,
                                 restSeconds: $settings.restSeconds,
                                 autoStartRest: $settings.autoStartRest,
                                 preWorkoutCountdown: $settings.preWorkoutCountdown,
                                 autoEndOnIdle: $settings.autoEndOnIdle,
                                 idleTimeoutMinutes: $settings.idleTimeoutMinutes,
                                 plateRounding: $settings.plateRounding,
                                 useHR: $settings.useHRMonitoring)
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
