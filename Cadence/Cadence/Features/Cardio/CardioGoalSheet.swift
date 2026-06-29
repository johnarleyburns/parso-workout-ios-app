import SwiftUI
import CadenceCore

struct CardioGoalSheet: View {
    let type: CardioType
    let onStart: (_ goalMeters: Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var customKm = ""
    @State private var preWorkoutCountdown: Int
    @State private var gpsHighAccuracy: Bool
    @State private var autoPause: Bool
    @State private var useHR: Bool

    private let presets: [(label: String, meters: Double)] = [
        ("5K", 5000), ("10K", 10000), ("Half Marathon", 21097), ("Marathon", 42195),
    ]

    init(type: CardioType, onStart: @escaping (Double?) -> Void) {
        self.type = type
        self.onStart = onStart
        let ws = WorkoutSettings.default
        self._preWorkoutCountdown = State(initialValue: ws.preWorkoutCountdown)
        self._gpsHighAccuracy = State(initialValue: ws.gpsHighAccuracy)
        self._autoPause = State(initialValue: ws.autoPause)
        self._useHR = State(initialValue: ws.useHRMonitoring)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        saveAndStart(nil)
                    } label: {
                        Label("No goal — just start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)
                    .accessibilityIdentifier("goal.none")
                    .listRowBackground(Color.clear)
                }
                Section("Distance goal") {
                    ForEach(presets, id: \.label) { preset in
                        Button {
                            saveAndStart(preset.meters)
                        } label: {
                            HStack {
                                Text(preset.label)
                                Spacer()
                                Text(Format.distance(preset.meters)).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("goal.preset.\(preset.label)")
                    }
                }
                Section("Custom (km)") {
                    HStack {
                        TextField("e.g. 7.5", text: $customKm)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("goal.customKm")
                        Button("Start") {
                            let km = Double(customKm.replacingOccurrences(of: ",", with: "."))
                            saveAndStart((km ?? 0) > 0 ? (km! * 1000) : nil)
                        }
                        .disabled((Double(customKm.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
                        .accessibilityIdentifier("goal.customStart")
                    }
                }
                Section {
                    Stepper("Get-ready countdown: \(preWorkoutCountdown > 0 ? "\(preWorkoutCountdown)s" : "off")",
                            value: $preWorkoutCountdown, in: 0...60, step: 5)
                        .accessibilityIdentifier("goal.countdown")
                }
                Section {
                    Toggle("High-accuracy GPS", isOn: $gpsHighAccuracy)
                        .accessibilityIdentifier("goal.gpsHighAccuracy")
                    Toggle("Auto-pause when stopped", isOn: $autoPause)
                        .accessibilityIdentifier("goal.autoPause")
                } header: {
                    Text("GPS")
                }
                Section {
                    Toggle("Use HR monitoring", isOn: $useHR)
                        .accessibilityIdentifier("goal.hrToggle")
                } footer: {
                    Text("Connect a chest strap or Apple Watch before the workout starts.")
                }
            }
            .navigationTitle("\(type.displayName) goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("goal.cancel")
                }
            }
            .onAppear { loadSettings() }
        }
    }

    private func loadSettings() {
        let ws = settings.lastCardioSettings
        preWorkoutCountdown = ws.preWorkoutCountdown
        gpsHighAccuracy = ws.gpsHighAccuracy
        autoPause = ws.autoPause
        useHR = ws.useHRMonitoring
    }

    private func saveAndStart(_ goalMeters: Double?) {
        let ws = WorkoutSettings(
            restSeconds: settings.lastCardioSettings.restSeconds,
            autoStartRest: settings.lastCardioSettings.autoStartRest,
            preWorkoutCountdown: preWorkoutCountdown,
            autoEndOnIdle: settings.lastCardioSettings.autoEndOnIdle,
            idleTimeoutMinutes: settings.lastCardioSettings.idleTimeoutMinutes,
            plateRounding: settings.lastCardioSettings.plateRounding,
            gpsHighAccuracy: gpsHighAccuracy,
            autoPause: autoPause,
            intervalColorBlind: settings.lastCardioSettings.intervalColorBlind,
            spokenCues: settings.lastCardioSettings.spokenCues,
            weeklyCardioMinutesGoal: settings.lastCardioSettings.weeklyCardioMinutesGoal,
            warmupMinutes: settings.lastCardioSettings.warmupMinutes,
            cooldownMinutes: settings.lastCardioSettings.cooldownMinutes,
            useHRMonitoring: useHR
        )
        settings.lastCardioSettings = ws
        settings.preWorkoutCountdown = preWorkoutCountdown
        settings.gpsHighAccuracy = gpsHighAccuracy
        settings.autoPause = autoPause
        settings.useHRMonitoring = useHR

        dismiss()
        onStart(goalMeters)
    }
}
