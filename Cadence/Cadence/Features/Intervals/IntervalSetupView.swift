import SwiftUI
import CadenceCore

/// Pick an interval protocol (field-testing §06, decisions #21/#22), then launch
/// the full-screen runner. HIIT → Tabata / Norwegian 4×4 / Custom; Boxing →
/// 3min·1min / 2min·30s / Custom.
struct IntervalSetupView: View {
    let type: WorkoutType   // .hiit or .boxing
    /// Called with the chosen plan; the presenter launches the runner so it
    /// unwinds back to Home (not this sheet) when the workout ends.
    let onSelect: (IntervalPlan) -> Void

    @Environment(\.dismiss) private var dismiss

    // Custom builder params.
    @State private var rounds = 8
    @State private var workSec = 30
    @State private var restSec = 30
    @State private var warmupMin = 5
    @State private var cooldownMin = 5

    var body: some View {
        NavigationStack {
            List {
                Section("Presets") {
                    if type == .hiit {
                        preset("Tabata", "8 × 20s / 10s", id: "tabata") { .tabata() }
                        preset("Norwegian 4×4", "4 × 4min / 3min", id: "norwegian") { .norwegian4x4() }
                    } else {
                        preset("3 min / 1 min", "12 rounds", id: "box-3-1") { .boxing(rounds: 12, round: 180, rest: 60) }
                        preset("2 min / 30 s", "12 rounds", id: "box-2-30") { .boxing(rounds: 12, round: 120, rest: 30) }
                    }
                }

                Section("Custom") {
                    Stepper("Rounds: \(rounds)", value: $rounds, in: 1...30)
                        .accessibilityIdentifier("interval.custom.rounds")
                    Stepper("Work: \(workSec)s", value: $workSec, in: 5...600, step: 5)
                    Stepper("Rest: \(restSec)s", value: $restSec, in: 0...600, step: 5)
                    Stepper("Warm-up: \(warmupMin) min", value: $warmupMin, in: 0...20)
                    Stepper("Cool-down: \(cooldownMin) min", value: $cooldownMin, in: 0...20)
                    Button {
                        choose(.custom(
                            name: type == .boxing ? "Boxing" : "HIIT",
                            warmup: TimeInterval(warmupMin * 60), rounds: rounds,
                            work: TimeInterval(workSec), rest: TimeInterval(restSec),
                            cooldown: TimeInterval(cooldownMin * 60)))
                    } label: { Label("Start Custom", systemImage: "play.fill") }
                        .accessibilityIdentifier("interval.preset.custom")
                }
            }
            .navigationTitle(type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("interval.cancel")
                }
            }
        }
    }

    private func choose(_ plan: IntervalPlan) {
        onSelect(plan)
        dismiss()
    }

    private func preset(_ title: String, _ subtitle: String, id: String,
                        _ make: @escaping () -> IntervalPlan) -> some View {
        Button {
            choose(make())
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier("interval.preset.\(id)")
    }
}

/// Identifiable launch descriptor so a plan + its HealthKit save-type can drive
/// `.fullScreenCover(item:)` from the presenter (Home).
struct IntervalLaunch: Identifiable {
    let id = UUID()
    let plan: IntervalPlan
    let saveType: CardioType
}
