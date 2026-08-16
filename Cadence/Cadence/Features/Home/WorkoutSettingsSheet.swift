import SwiftUI

struct WorkoutSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var warmupMinutes: Int
    @Binding var cooldownMinutes: Int
    @Binding var restSeconds: Int
    @Binding var autoStartRest: Bool
    @Binding var preWorkoutCountdown: Int
    @Binding var autoEndOnIdle: Bool
    @Binding var idleTimeoutMinutes: Int
    @Binding var plateRounding: Bool
    @Binding var useHR: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Warm-up and cool-down") {
                    Stepper("Warm-up: \(warmupMinutes) min", value: $warmupMinutes, in: 0...30)
                        .accessibilityIdentifier("editor.warmup")
                    Stepper("Cool-down: \(cooldownMinutes) min", value: $cooldownMinutes, in: 0...30)
                        .accessibilityIdentifier("editor.cooldown")
                }
                Section("Workout flow") {
                    Stepper("Get-ready countdown: \(preWorkoutCountdown)s",
                            value: $preWorkoutCountdown, in: 0...60, step: 5)
                        .accessibilityIdentifier("editor.countdown")
                    Stepper("Rest timer: \(restSeconds)s",
                            value: $restSeconds, in: 15...600, step: 15)
                        .accessibilityIdentifier("editor.restSeconds")
                    Toggle("Auto-start rest timer", isOn: $autoStartRest)
                        .accessibilityIdentifier("editor.autoRest")
                }
                Section("Loading") {
                    Toggle("Round weights to nearest plate", isOn: $plateRounding)
                        .accessibilityIdentifier("editor.plateRounding")
                }
                Section {
                    Toggle("Check in when idle", isOn: $autoEndOnIdle)
                        .accessibilityIdentifier("editor.autoEndOnIdle")
                    Stepper("Ask after \(idleTimeoutMinutes) min idle",
                            value: $idleTimeoutMinutes, in: 2...30)
                        .disabled(!autoEndOnIdle)
                        .accessibilityIdentifier("editor.idleTimeout")
                } header: {
                    Text("Idle Check-In")
                } footer: {
                    Text("If you don't respond, the workout pauses. It never ends on its own.")
                }
                Section {
                    Toggle("Use HR monitoring", isOn: $useHR)
                        .accessibilityIdentifier("editor.hrToggle")
                } header: {
                    Text("Heart rate")
                } footer: {
                    Text("Connect a Bluetooth chest strap before the workout starts.")
                }
            }
            .navigationTitle("Workout Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("editor.settingsSheet")
    }
}
