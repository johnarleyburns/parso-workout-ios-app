import SwiftUI
import CadenceCore
import CadenceFeatures

struct CardioGoalSheet: View {
    let type: CardioType
    let onSchedule: ((Date) async throws -> Void)?
    let onStart: (_ goalMeters: Double?, _ indoors: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var customKm = ""
    @State private var preWorkoutCountdown: Int
    @State private var gpsHighAccuracy: Bool
    @State private var autoPause: Bool
    @State private var useHR: Bool
    @State private var indoors = true
    @State private var selectedGoalMeters: Double?
    @State private var schedulePresented = false

    private let presets: [(label: String, meters: Double)] = [
        ("5K", 5000), ("10K", 10000), ("Half Marathon", 21097), ("Marathon", 42195),
    ]

    init(type: CardioType,
         onSchedule: ((Date) async throws -> Void)? = nil,
         onStart: @escaping (Double?, Bool) -> Void) {
        self.type = type
        self.onSchedule = onSchedule
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
                        saveAndStart()
                    } label: {
                        Label("Start \(type.displayName)", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .cadenceGlassButton(prominent: true, tint: .green)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .accessibilityIdentifier("goal.none")
                    .listRowBackground(Color.clear)

                    if onSchedule != nil {
                        Button {
                            schedulePresented = true
                        } label: {
                            Label("Schedule \(type.displayName)", systemImage: "calendar.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("goal.schedule")
                        .listRowBackground(Color.clear)
                    }

                    Menu {
                        Button("Indoors") { indoors = true }
                            .accessibilityIdentifier("goal.indoors")
                        Button("Outdoors — use GPS") { indoors = false }
                            .accessibilityIdentifier("goal.outdoors")
                    } label: {
                        HStack {
                            Label("Indoors/Outdoors", systemImage: indoors ? "house.fill" : "location.fill")
                            Spacer()
                            Text(indoors ? "Indoors" : "Outdoors")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("goal.indoorsOutdoors")
                    .listRowBackground(Color.clear)
                }
                if !indoors {
                    Section("Distance goal") {
                        ForEach(presets, id: \.label) { preset in
                            Button {
                                selectedGoalMeters = preset.meters
                            } label: {
                                HStack {
                                    Text(preset.label)
                                    Spacer()
                                    if selectedGoalMeters == preset.meters {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
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
                            Button("Use") {
                                let km = Double(customKm.replacingOccurrences(of: ",", with: "."))
                                selectedGoalMeters = (km ?? 0) > 0 ? (km! * 1000) : nil
                            }
                            .disabled((Double(customKm.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
                            .accessibilityIdentifier("goal.customStart")
                        }
                    }
                }
                Section {
                    Stepper("Get-ready countdown: \(preWorkoutCountdown > 0 ? "\(preWorkoutCountdown)s" : "off")",
                            value: $preWorkoutCountdown, in: 0...60, step: 5)
                        .accessibilityIdentifier("goal.countdown")
                }
                if !indoors {
                    Section {
                        Toggle("High-accuracy GPS", isOn: $gpsHighAccuracy)
                            .accessibilityIdentifier("goal.gpsHighAccuracy")
                        Toggle("Auto-pause when stopped", isOn: $autoPause)
                            .accessibilityIdentifier("goal.autoPause")
                    } header: {
                        Text("GPS")
                    }
                }
                Section {
                    Toggle("Use HR monitoring", isOn: $useHR)
                        .accessibilityIdentifier("goal.hrToggle")
                } footer: {
                    Text("Connect a Bluetooth chest strap before the workout starts.")
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
            .sheet(isPresented: $schedulePresented) {
                if let onSchedule {
                    ScheduleWorkoutSheet(title: type.displayName, onSave: onSchedule)
                }
            }
        }
    }

    private func loadSettings() {
        let ws = settings.lastCardioSettings
        preWorkoutCountdown = ws.preWorkoutCountdown
        gpsHighAccuracy = ws.gpsHighAccuracy
        autoPause = ws.autoPause
        useHR = ws.useHRMonitoring
    }

    private func saveAndStart() {
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
        onStart(indoors ? nil : selectedGoalMeters, indoors)
    }
}
