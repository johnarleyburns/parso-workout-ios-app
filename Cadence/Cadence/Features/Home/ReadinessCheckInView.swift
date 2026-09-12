import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct ReadinessCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var muscleSoreness: Int
    @State private var fatigueEnergy: Int
    @State private var sleepQuality: Int
    @State private var stressMood: Int
    @State private var painOrIllness: Bool
    let existing: ReadinessEntry?

    init(existing: ReadinessEntry? = nil) {
        self.existing = existing
        _muscleSoreness = State(initialValue: existing?.muscleSoreness ?? 3)
        _fatigueEnergy = State(initialValue: existing?.fatigueEnergy ?? 3)
        _sleepQuality = State(initialValue: existing?.sleepQuality ?? 3)
        _stressMood = State(initialValue: existing?.stressMood ?? 3)
        _painOrIllness = State(initialValue: existing?.hasPainOrIllnessConcern ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    rating("Muscle soreness", value: $muscleSoreness,
                           low: "Very sore", high: "No soreness")
                    rating("Energy", value: $fatigueEnergy,
                           low: "Exhausted", high: "Full of energy")
                    rating("Sleep", value: $sleepQuality,
                           low: "Terrible", high: "Great")
                    rating("Stress / mood", value: $stressMood,
                           low: "Very stressed", high: "Relaxed")
                } header: {
                    Text("How are you today?")
                } footer: {
                    Text("This is optional context for Cladiron's coach. It can suggest a lighter session, but it never diagnoses or forces a change.")
                }

                Section {
                    Toggle("Pain or illness concern", isOn: $painOrIllness)
                        .accessibilityIdentifier("readiness.painOrIllness")
                } footer: {
                    Text("If this is selected, take care of yourself and consider professional advice. The coach will avoid presenting hard recommendations.")
                }

                Section {
                    Button(existing == nil ? "Save check-in" : "Update check-in") {
                        save()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("readiness.save")
                }
            }
            .navigationTitle(existing == nil ? "Readiness" : "Update readiness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func rating(_ title: String, value: Binding<Int>, low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)/5")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0.rounded()) }),
                   in: 1...5, step: 1)
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readiness.\(title.lowercased().replacingOccurrences(of: " ", with: "."))")
    }

    private func save() {
        guard ReadinessCheckInPresenter.validate(
            muscleSoreness: muscleSoreness, fatigueEnergy: fatigueEnergy,
            sleepQuality: sleepQuality, stressMood: stressMood) else { return }
        let entry = existing ?? ReadinessEntry(date: Date())
        entry.date = Date()
        entry.muscleSoreness = muscleSoreness
        entry.fatigueEnergy = fatigueEnergy
        entry.sleepQuality = sleepQuality
        entry.stressMood = stressMood
        entry.hasPainOrIllnessConcern = painOrIllness
        entry.updatedAt = Date()
        if existing == nil { context.insert(entry) }
        try? context.save()
        NotificationCenter.default.post(name: .readinessCheckInChanged, object: nil)
        dismiss()
    }
}
