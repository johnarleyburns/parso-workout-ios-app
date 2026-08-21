import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Pool swim recorder (round4b feedback #3): time + lap count only — no GPS,
/// distance, or calorie estimate. Set a lap goal, start the clock, tap to count
/// laps, then End to save. Deliberately minimal, per "just time and number of
/// target laps, nothing complex."
struct SwimRecordView: View {
    /// Notifies the presenter (Home) the instant a workout is persisted, so its
    /// history-derived surfaces refresh without waiting for app re-entry.
    var onSaved: (CardioWorkout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @State private var started = false
    @State private var startDate = Date()
    @State private var now = Date()
    @State private var targetLaps = 20
    @State private var laps = 0
    @State private var finishedSummary: WorkoutSummaryData?
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let finishedSummary {
                // The swim is already saved; show its summary (laps + duration).
                WorkoutSummaryView(data: finishedSummary, onDone: { dismiss() })
            } else {
                NavigationStack {
                    Group {
                        if started { liveScreen } else { setupScreen }
                    }
                    .navigationTitle(started ? "Swimming" : "Swim")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }.accessibilityIdentifier("swim.cancel")
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(started)
        .keepAwake(started && finishedSummary == nil)
        .onReceive(tick) { now = $0 }
    }

    private var setupScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.pool.swim").scaledSystemFont(64, relativeTo: .largeTitle).foregroundStyle(.tint)
            Stepper(value: $targetLaps, in: 1...200) {
                HStack { Text("Target laps"); Spacer(); Text("\(targetLaps)").monospacedDigit() }
            }
            .accessibilityIdentifier("swim.targetLaps")

            HStack {
                @Bindable var settings = settings
                Toggle("Use HR monitoring", isOn: $settings.useHRMonitoring)
                    .accessibilityIdentifier("swim.hrToggle")
            }

            Button {
                startDate = Date(); now = Date(); started = true
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
            }
            .cadenceGlassButton(prominent: true, tint: .blue)
            .accessibilityIdentifier("swim.start")
            Spacer()
        }
        .padding()
    }

    private var liveScreen: some View {
        VStack(spacing: 28) {
            HStack { WallClockLabel(); Spacer() }
            Text(Format.duration(now.timeIntervalSince(startDate)))
                .scaledSystemFont(56, relativeTo: .largeTitle, weight: .bold, design: .rounded).monospacedDigit()
                .accessibilityIdentifier("swim.elapsed")

            VStack(spacing: 4) {
                Text("\(laps)/\(targetLaps)")
                    .scaledSystemFont(48, relativeTo: .largeTitle, weight: .bold, design: .rounded).monospacedDigit()
                    .accessibilityIdentifier("swim.laps")
                Text("laps").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 32) {
                Button { if laps > 0 { laps -= 1 } } label: {
                    Image(systemName: "minus.circle.fill").scaledSystemFont(48, relativeTo: .largeTitle)
                }
                .accessibilityIdentifier("swim.lapMinus")
                .accessibilityLabel("Remove a lap")
                Button { laps += 1 } label: {
                    Image(systemName: "plus.circle.fill").scaledSystemFont(48, relativeTo: .largeTitle)
                }
                .accessibilityIdentifier("swim.lapPlus")
                .accessibilityLabel("Add a lap")
            }
            .tint(.blue)

            Spacer()

            Button(action: endSwim) {
                Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(.red)
            .accessibilityIdentifier("swim.end")
        }
        .padding()
    }

    private func endSwim() {
        // A watch session started at the HR gate outlives the recorder unless we
        // tear it down here (field-test batch 2026-08-20 issue 5).
        model.stopWatchWorkout()
        let end = Date()
        let summary = CardioWorkoutSummary(id: UUID(), type: .swim, start: startDate, end: end,
                                           hrSamples: [], route: [])
        Task {
            let hkID = await model.health.saveCardioWorkout(summary)
            if let saved = try? WorkoutRepository.saveSwim(
                start: startDate, end: end,
                laps: laps, targetLaps: targetLaps,
                healthKitWorkoutUUID: hkID, in: context) {
                onSaved(saved)
                finishedSummary = WorkoutSummaryData.from(cardio: saved)
            } else {
                dismiss()
            }
        }
    }
}
