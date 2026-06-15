import SwiftUI
import CadenceCore

/// Optional distance-goal chooser shown before a run/walk/cycle starts (feedback
/// batch 8). The user can pick a common target (5K/10K), type a custom distance, or
/// skip — "No goal" preserves the prior behavior. Returns the goal in meters (nil =
/// none) and the chosen cardio type so Home can launch the recorder.
struct CardioGoalSheet: View {
    let type: CardioType
    /// Called with the chosen goal in meters (nil ⇒ no goal) when the user starts.
    let onStart: (_ goalMeters: Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customKm = ""

    private let presets: [(label: String, meters: Double)] = [
        ("5K", 5000), ("10K", 10000), ("Half Marathon", 21097), ("Marathon", 42195),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        onStart(nil); dismiss()
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
                            onStart(preset.meters); dismiss()
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
                            onStart((km ?? 0) > 0 ? (km! * 1000) : nil); dismiss()
                        }
                        .disabled((Double(customKm.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
                        .accessibilityIdentifier("goal.customStart")
                    }
                }
            }
            .navigationTitle("\(type.displayName) goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("goal.cancel")
                }
            }
        }
    }
}
