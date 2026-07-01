import SwiftUI
import CadenceCore

struct TimerCardioSetup: Identifiable {
    let id = UUID()
    let type: CardioType
    let suggestedMinutes: Int?
}

struct TimerCardioSetupView: View {
    let type: CardioType
    var suggestedMinutes: Int? = nil
    var onSaved: (CardioWorkout) -> Void = { _ in }

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var started = false
    @State private var preWorkoutCountdown: Int
    @State private var useHR: Bool

    init(type: CardioType, suggestedMinutes: Int? = nil, onSaved: @escaping (CardioWorkout) -> Void = { _ in }) {
        self.type = type
        self.suggestedMinutes = suggestedMinutes
        self.onSaved = onSaved
        let ws = WorkoutSettings.default
        self._preWorkoutCountdown = State(initialValue: ws.preWorkoutCountdown)
        self._useHR = State(initialValue: ws.useHRMonitoring)
    }

    var body: some View {
        if started {
            RecordCardioView(initialType: type, captureHR: settings.useHRMonitoring, onSaved: onSaved)
        } else {
            setupScreen
        }
    }

    private var setupScreen: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: type.symbol).scaledSystemFont(64, relativeTo: .largeTitle).foregroundStyle(.tint)
                Text(type.displayName).font(.title2.bold())

                if let suggestedMinutes {
                    Label("Coach suggests \(suggestedMinutes) min", systemImage: "clock")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("timerCardio.suggested")
                }

                HStack {
                    Stepper("Get-ready countdown: \(preWorkoutCountdown > 0 ? "\(preWorkoutCountdown)s" : "off")",
                            value: $preWorkoutCountdown, in: 0...60, step: 5)
                        .accessibilityIdentifier("timerCardio.countdown")
                }

                HStack {
                    Toggle("Use HR monitoring", isOn: $useHR)
                        .accessibilityIdentifier("timerCardio.hrToggle")
                }

                Button {
                    saveAndStart()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
                }
                .cadenceGlassButton(prominent: true, tint: .green)
                .accessibilityIdentifier("timerCardio.start")

                Spacer()
            }
            .padding()
            .navigationTitle("\(type.displayName) setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("timerCardio.cancel")
                }
            }
            .onAppear { loadSettings() }
        }
    }

    private func loadSettings() {
        let ws = settings.lastCardioSettings
        preWorkoutCountdown = ws.preWorkoutCountdown
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
            gpsHighAccuracy: settings.lastCardioSettings.gpsHighAccuracy,
            autoPause: settings.lastCardioSettings.autoPause,
            intervalColorBlind: settings.lastCardioSettings.intervalColorBlind,
            spokenCues: settings.lastCardioSettings.spokenCues,
            weeklyCardioMinutesGoal: settings.lastCardioSettings.weeklyCardioMinutesGoal,
            warmupMinutes: settings.lastCardioSettings.warmupMinutes,
            cooldownMinutes: settings.lastCardioSettings.cooldownMinutes,
            useHRMonitoring: useHR
        )
        settings.lastCardioSettings = ws
        settings.preWorkoutCountdown = preWorkoutCountdown
        settings.useHRMonitoring = useHR
        started = true
    }
}
