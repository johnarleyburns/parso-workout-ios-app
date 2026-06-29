import SwiftUI
import CadenceCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settingsObject
    @Environment(ContributionCoordinator.self) private var contributions

    @State private var healthStatus: HealthAuthorizationStatus = .notDetermined
    @State private var primingPresented = false

    var body: some View {
        @Bindable var settings = settingsObject
        Form {
            Section {
                Picker("Training goal", selection: $settings.trainingGoal) {
                    ForEach(TrainingGoal.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.coach.goal")
                Picker("Experience", selection: $settings.experienceLevel) {
                    ForEach(ExperienceLevel.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.coach.experience")
                NavigationLink {
                    CoachSchedulePreferencesView()
                } label: {
                    Label("Schedule preferences", systemImage: "calendar.badge.clock")
                }
                .accessibilityIdentifier("settings.coach.schedulePreferences")
            } header: {
                Text("Coach")
            } footer: {
                Text("Your coach uses these to tailor its insights — goal sets the load/effort it looks for, experience scales the weekly volume targets. Coaching only, not medical advice.")
            }

            Section("Units & Records") {
                Picker("Weight unit", selection: $settings.unit) {
                    ForEach(MeasurementUnitPreference.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.unit")
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

            Section("Workout") {
                Stepper("Rest timer: \(settings.restSeconds)s",
                        value: $settings.restSeconds, in: 15...600, step: 15)
                    .accessibilityIdentifier("settings.restSeconds")
                Toggle("Auto-start rest timer", isOn: $settings.autoStartRest)
                    .accessibilityIdentifier("settings.autoRest")
            }

            Section("Workout start") {
                Stepper(settings.preWorkoutCountdown == 0
                        ? "Get-ready countdown: off"
                        : "Get-ready countdown: \(settings.preWorkoutCountdown)s",
                        value: $settings.preWorkoutCountdown, in: 0...60, step: 5)
                    .accessibilityIdentifier("settings.preWorkoutCountdown")
            }

            Section {
                Toggle("Auto-end when idle", isOn: $settings.autoEndOnIdle)
                    .accessibilityIdentifier("settings.autoEndOnIdle")
                Stepper("Auto-end after \(settings.idleTimeoutMinutes) min idle",
                        value: $settings.idleTimeoutMinutes, in: 2...30)
                    .disabled(!settings.autoEndOnIdle)
                    .accessibilityIdentifier("settings.idleTimeout")
            } header: {
                Text("Idle Auto-End")
            } footer: {
                Text("When on, a strength workout that's been idle for the time above auto-saves. Turn off to keep it running until you end it yourself.")
            }

            Section("Strength") {
                Toggle("Round weights to nearest plate", isOn: $settings.plateRounding)
                    .accessibilityIdentifier("settings.plateRounding")
            }

            Section("Cardio") {
                Toggle("High-accuracy GPS", isOn: $settings.gpsHighAccuracy)
                    .accessibilityIdentifier("settings.gpsHighAccuracy")
                Toggle("Auto-pause when stopped", isOn: $settings.autoPause)
                    .accessibilityIdentifier("settings.autoPause")
            }

            Section("Intervals") {
                Toggle("Color-blind palette", isOn: $settings.intervalColorBlind)
                    .accessibilityIdentifier("settings.intervalColorBlind")
                Toggle("Spoken announcements", isOn: $settings.spokenCues)
                    .accessibilityIdentifier("settings.spokenCues")
            }

            Section("Goals") {
                Stepper("Weekly cardio goal: \(settings.weeklyCardioMinutesGoal) min",
                        value: $settings.weeklyCardioMinutesGoal, in: 50...1000, step: 10)
                    .accessibilityIdentifier("settings.cardioGoal")
            }

            Section {
                Stepper("Warm-up: \(settings.warmupMinutes) min",
                        value: $settings.warmupMinutes, in: 1...30)
                    .accessibilityIdentifier("settings.warmupMinutes")
                Stepper("Cool-down: \(settings.cooldownMinutes) min",
                        value: $settings.cooldownMinutes, in: 1...30)
                    .accessibilityIdentifier("settings.cooldownMinutes")
            } header: {
                Text("Warm-up & Cool-down")
            } footer: {
                Text("Optional guided timers for strength workouts — start with a warm-up, or wind down with a cool-down before finishing.")
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
                Text("Cladiron is free and open-source. A one-time tip is an optional way to support development — never required.")
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
