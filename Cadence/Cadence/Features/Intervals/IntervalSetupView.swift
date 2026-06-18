import SwiftUI
import CadenceCore

/// Pick an interval protocol, then tap **START** (field-test round 3 — selecting
/// a preset no longer auto-launches). HIIT offers Tabata, Norwegian 4×4, Gibala,
/// SIT (Wingate), 10-20-30, REHIT, and Custom; Boxing shows Details directly with
/// round-style steppers (no presets).
struct IntervalSetupView: View {
    let type: WorkoutType   // .hiit or .boxing
    /// Called with the chosen plan; the presenter runs the countdown then the
    /// runner so it unwinds back to Home (not this sheet) when the workout ends.
    let onSelect: (IntervalPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var selectedID: String = ""

    // Custom builder params.
    @State private var rounds: Int
    @State private var workSec: Int
    @State private var restSec: Int
    @State private var warmupMin = 5
    @State private var cooldownMin = 5

    init(type: WorkoutType, onSelect: @escaping (IntervalPlan) -> Void) {
        self.type = type
        self.onSelect = onSelect
        if type == .boxing {
            _rounds = State(initialValue: 8)
            _workSec = State(initialValue: 180)
            _restSec = State(initialValue: 60)
        } else {
            _rounds = State(initialValue: 8)
            _workSec = State(initialValue: 30)
            _restSec = State(initialValue: 30)
        }
    }

    private struct Preset: Identifiable { let id: String; let title: String; let subtitle: String; let make: () -> IntervalPlan }

    private var presets: [Preset] {
        if type == .boxing { return [] }
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
        if type == .boxing { return customPlan() }
        if selectedID == "custom" { return customPlan() }
        return (presets.first { $0.id == selectedID } ?? presets[0]).make()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if type == .hiit {
                        Section("Presets") {
                            ForEach(presets) { p in
                                row(p.id, p.title, p.subtitle)
                            }
                        }
                    }
                    Section(sectionTitle) {
                        Stepper("Warm-up: \(warmupMin) min", value: $warmupMin, in: 0...20)
                        Stepper("Rounds: \(rounds)", value: $rounds, in: 1...30)
                            .accessibilityIdentifier("interval.custom.rounds")
                        Stepper("Fighting: \(formatMinSec(workSec))", value: $workSec, in: 10...600, step: stepSize)
                        Stepper("Rest: \(restSec) sec", value: $restSec, in: 0...300, step: stepSize)
                        Stepper("Cool-down: \(cooldownMin) min", value: $cooldownMin, in: 0...20)
                    if type == .hiit {
                        rowLabel("custom", "Custom", "your settings")
                    }
                }
                Section {
                    @Bindable var settings = settings
                    Toggle("Use HR monitoring", isOn: $settings.useHRMonitoring)
                        .accessibilityIdentifier("interval.hrToggle")
                } footer: {
                    Text("Connect a chest strap or Apple Watch before the workout starts.")
                }
                }

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
            .onAppear { if selectedID.isEmpty, !presets.isEmpty { selectedID = presets[0].id } }
        }
    }

    private var sectionTitle: String { type == .boxing ? "Details" : "Custom" }
    private var stepSize: Int { type == .boxing ? 30 : 5 }

    private func formatMinSec(_ totalSec: Int) -> String {
        "\(totalSec / 60):\(String(format: "%02d", totalSec % 60))"
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
