import SwiftUI
import CadenceCore

/// App settings (FR-4.1, 4.5; FR-1 preferences; FR-6 data) — resolves the
/// REQUIREMENTS §9 open questions with user-overridable defaults.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settingsObject

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
                    Picker("PR rule", selection: $settings.prRule) {
                        ForEach(PRRule.allCases) { Text($0.displayName).tag($0) }
                    }
                    .accessibilityIdentifier("settings.prRule")
                    Picker("1RM formula", selection: $settings.formula) {
                        ForEach(OneRepMaxFormula.allCases) { Text($0.displayName).tag($0) }
                    }
                    .accessibilityIdentifier("settings.formula")
                }

                Section("Workout") {
                    Stepper("Step goal: \(Format.integer(settings.stepGoal))",
                            value: $settings.stepGoal, in: 1000...50000, step: 500)
                        .accessibilityIdentifier("settings.stepGoal")
                    Stepper("Rest timer: \(settings.restSeconds)s",
                            value: $settings.restSeconds, in: 15...600, step: 15)
                        .accessibilityIdentifier("settings.restSeconds")
                    Toggle("Auto-start rest timer", isOn: $settings.autoStartRest)
                        .accessibilityIdentifier("settings.autoRest")
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
                    Toggle("iCloud Sync", isOn: $settings.cloudSyncEnabled)
                        .accessibilityIdentifier("settings.cloudSync")
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Off by default — Cadence runs fully on this device. When on, your data syncs through your private iCloud database. Takes effect after the app restarts.")
                }

                Section("Data") {
                    NavigationLink {
                        ImportView()
                    } label: { Label("Import", systemImage: "square.and.arrow.down") }
                        .accessibilityIdentifier("settings.import")
                    NavigationLink {
                        ExportView()
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("settings.export")
                }

                // Field-testing §06 polish — appended so existing rows keep their
                // positions (and tests their reachability).
                Section("Workout start") {
                    Stepper(settings.preWorkoutCountdown == 0
                            ? "Get-ready countdown: off"
                            : "Get-ready countdown: \(settings.preWorkoutCountdown)s",
                            value: $settings.preWorkoutCountdown, in: 0...60, step: 5)
                        .accessibilityIdentifier("settings.preWorkoutCountdown")
                }

                Section("Strength") {
                    Stepper("Auto-end after \(settings.idleTimeoutMinutes) min idle",
                            value: $settings.idleTimeoutMinutes, in: 2...30)
                        .accessibilityIdentifier("settings.idleTimeout")
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
