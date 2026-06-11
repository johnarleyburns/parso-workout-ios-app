import SwiftUI
import CadenceCore

/// Pick an interval protocol, then tap **START** (field-test round 3 — selecting
/// a preset no longer auto-launches). HIIT offers Tabata, Norwegian 4×4, Gibala,
/// SIT (Wingate), 10-20-30, REHIT, and Custom; Boxing offers the round presets.
struct IntervalSetupView: View {
    let type: WorkoutType   // .hiit or .boxing
    /// Called with the chosen plan; the presenter runs the countdown then the
    /// runner so it unwinds back to Home (not this sheet) when the workout ends.
    let onSelect: (IntervalPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String = ""

    // Custom builder params.
    @State private var rounds = 8
    @State private var workSec = 30
    @State private var restSec = 30
    @State private var warmupMin = 5
    @State private var cooldownMin = 5

    private struct Preset: Identifiable { let id: String; let title: String; let subtitle: String; let make: () -> IntervalPlan }

    private var presets: [Preset] {
        if type == .boxing {
            return [
                Preset(id: "box-3-1", title: "3 min / 1 min", subtitle: "12 rounds") { .boxing(rounds: 12, round: 180, rest: 60) },
                Preset(id: "box-2-30", title: "2 min / 30 s", subtitle: "12 rounds") { .boxing(rounds: 12, round: 120, rest: 30) },
            ]
        }
        return [
            Preset(id: "tabata", title: "Tabata", subtitle: "8 × 20s / 10s") { .tabata() },
            Preset(id: "norwegian", title: "Norwegian 4×4", subtitle: "4 × 4min / 3min") { .norwegian4x4() },
            Preset(id: "gibala", title: "Gibala", subtitle: "8 × 60s / 60s · ~20 min") { .gibala() },
            Preset(id: "sit", title: "SIT (Wingate)", subtitle: "4 × 30s all-out / 4 min") { .sit() },
            Preset(id: "ten", title: "10-20-30", subtitle: "5 × (30/20/10), 3 sets") { .tenTwentyThirty() },
            Preset(id: "rehit", title: "REHIT", subtitle: "2 × 20s sprint / 3 min") { .rehit() },
        ]
    }

    private func customPlan() -> IntervalPlan {
        .custom(name: type == .boxing ? "Boxing" : "HIIT",
                warmup: TimeInterval(warmupMin * 60), rounds: rounds,
                work: TimeInterval(workSec), rest: TimeInterval(restSec),
                cooldown: TimeInterval(cooldownMin * 60))
    }
    private func selectedPlan() -> IntervalPlan {
        if selectedID == "custom" { return customPlan() }
        return (presets.first { $0.id == selectedID } ?? presets[0]).make()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("Presets") {
                        ForEach(presets) { p in
                            row(p.id, p.title, p.subtitle)
                        }
                    }
                    Section("Custom") {
                        Stepper("Rounds: \(rounds)", value: $rounds, in: 1...30)
                            .accessibilityIdentifier("interval.custom.rounds")
                        Stepper("Work: \(workSec)s", value: $workSec, in: 5...600, step: 5)
                        Stepper("Rest: \(restSec)s", value: $restSec, in: 0...600, step: 5)
                        Stepper("Warm-up: \(warmupMin) min", value: $warmupMin, in: 0...20)
                        Stepper("Cool-down: \(cooldownMin) min", value: $cooldownMin, in: 0...20)
                        rowLabel("custom", "Custom", "your settings")
                    }
                }

                // One prominent START (was an auto-launch / "Start Custom").
                Button {
                    onSelect(selectedPlan())
                    dismiss()
                } label: {
                    Label("START", systemImage: "play.fill")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .accessibilityIdentifier("interval.start")
            }
            .navigationTitle(type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("interval.cancel")
                }
            }
            .onAppear { if selectedID.isEmpty { selectedID = presets[0].id } }
        }
    }

    private func row(_ id: String, _ title: String, _ subtitle: String) -> some View {
        Button { selectedID = id } label: { rowContent(id, title, subtitle) }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("interval.preset.\(id)")
    }
    private func rowLabel(_ id: String, _ title: String, _ subtitle: String) -> some View {
        Button { selectedID = id } label: { rowContent(id, title, subtitle) }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("interval.preset.\(id)")
    }
    private func rowContent(_ id: String, _ title: String, _ subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: selectedID == id ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selectedID == id ? Color.accentColor : Color.secondary)
        }
    }
}

/// Identifiable launch descriptor so a plan + its HealthKit save-type can drive
/// `.fullScreenCover(item:)` from the presenter (Home).
struct IntervalLaunch: Identifiable {
    let id = UUID()
    let plan: IntervalPlan
    let saveType: CardioType
}
