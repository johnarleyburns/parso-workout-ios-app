import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct ManualStrengthItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var item: StrengthItem
    @State private var exerciseName: String
    @State private var pickerPresented = false
    @State private var sets: [ManualSetDraft]
    let onSave: (WorkoutItem) -> Void

    init(item: StrengthItem, onSave: @escaping (WorkoutItem) -> Void) {
        self._item = State(initialValue: item)
        let name = ExerciseLibrary.starter.first {
            $0.sourceExerciseID == item.exerciseKey.raw || ExerciseLibrary.lookupKey($0.name) == item.exerciseKey.raw
        }?.name ?? item.exerciseKey.raw.replacingOccurrences(of: "_", with: " ").capitalized
        self._exerciseName = State(initialValue: name)
        self._sets = State(initialValue: item.sets.map(ManualSetDraft.init))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    Button {
                        pickerPresented = true
                    } label: {
                        HStack {
                            Text(exerciseName).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("manualStrength.chooseExercise")
                }

                Section("Sets") {
                    ForEach($sets) { $set in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Set \(set.index + 1)").font(.headline)
                                Spacer()
                                Button(role: .destructive) {
                                    sets.removeAll { $0.id == set.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                            Picker("Type", selection: $set.kind) {
                                ForEach([SetKind.warmup, .working, .backoff, .amrap, .drop], id: \.self) { kind in
                                    Text(kind.rawValue.capitalized).tag(kind)
                                }
                            }
                            TextField("Reps or AMRAP", text: $set.repsText)
                                .keyboardType(.numbersAndPunctuation)
                            Picker("Load", selection: $set.loadChoice) {
                                ForEach(LoadChoice.allCases, id: \.self) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                            if set.loadChoice == .absolute || set.loadChoice == .percentage {
                                TextField(set.loadChoice == .absolute ? "Weight (kg)" : "% 1RM",
                                          text: $set.loadText)
                                    .keyboardType(.decimalPad)
                            }
                            TextField("Rest seconds", text: $set.restText)
                                .keyboardType(.numberPad)
                            TextField("Target RPE (optional)", text: $set.rpeText)
                                .keyboardType(.decimalPad)
                        }
                        .padding(.vertical, 4)
                    }
                    Button {
                        sets.append(ManualSetDraft(index: sets.count))
                    } label: {
                        Label("Duplicate last set", systemImage: "plus.circle")
                    }
                    .disabled(sets.isEmpty)
                    .accessibilityIdentifier("manualStrength.duplicateSet")
                }
            }
            .navigationTitle("Strength item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("manualStrength.save")
                }
            }
            .sheet(isPresented: $pickerPresented) {
                ExercisePickerView(action: .use) { exercise in
                    exerciseName = exercise.name
                    item.exerciseKey = ExerciseKey(raw: exercise.sourceExerciseID ?? ExerciseLibrary.lookupKey(exercise.name))
                    pickerPresented = false
                }
            }
        }
    }

    private func save() {
        let mapped = sets.enumerated().map { index, draft in
            draft.prescribedSet(index: index)
        }
        item.sets = mapped.isEmpty ? [PrescribedSet(setIndex: 0, repTarget: .exact(8))] : mapped
        onSave(.strength(item))
    }
}

enum LoadChoice: String, CaseIterable, Hashable {
    case unspecified, absolute, percentage, bodyweight

    var title: String {
        switch self {
        case .unspecified: return "No load"
        case .absolute: return "Weight"
        case .percentage: return "% 1RM"
        case .bodyweight: return "Bodyweight"
        }
    }
}

struct ManualSetDraft: Identifiable {
    let id: UUID
    var index: Int
    var kind: SetKind = .working
    var repsText: String = "8"
    var loadChoice: LoadChoice = .unspecified
    var loadText: String = ""
    var restText: String = "90"
    var rpeText: String = ""

    init(id: UUID = UUID(), index: Int = 0) {
        self.id = id
        self.index = index
    }

    init(set: PrescribedSet) {
        self.id = set.id
        self.index = set.setIndex
        self.kind = set.kind
        switch set.repTarget {
        case let .exact(reps): self.repsText = String(reps)
        case let .range(min, max): self.repsText = "\(min)-\(max)"
        case let .amrap(minimum): self.repsText = minimum.map { "AMRAP \($0)" } ?? "AMRAP"
        case let .duration(seconds): self.repsText = String(seconds)
        case let .distance(meters): self.repsText = String(meters)
        }
        switch set.load {
        case let .absoluteWeight(value, _): self.loadChoice = .absolute; self.loadText = String(value)
        case let .percent1RM(percent, _): self.loadChoice = .percentage; self.loadText = String(percent * 100)
        case .bodyweight: self.loadChoice = .bodyweight
        default: self.loadChoice = .unspecified
        }
        self.restText = set.restSeconds.map(String.init) ?? "90"
        self.rpeText = set.targetRPE.map { String($0) } ?? ""
    }

    func prescribedSet(index: Int) -> PrescribedSet {
        let repTarget: RepTarget = {
            let normalized = repsText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if normalized.hasPrefix("AMRAP") {
                let minimum = normalized.split(separator: " ").dropFirst().first.flatMap { Int($0) }
                return .amrap(minimum: minimum)
            }
            let parts = normalized.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { return .range(min: max(1, parts[0]), max: max(parts[0], parts[1])) }
            return .exact(max(1, Int(normalized) ?? 8))
        }()
        let load: LoadPrescription
        switch loadChoice {
        case .unspecified: load = .unspecified
        case .absolute: load = .absoluteWeight(value: max(0, Double(loadText) ?? 0), unit: .kg)
        case .percentage: load = .percent1RM(percent: max(0, Double(loadText) ?? 0) / 100, calculatedWeight: nil)
        case .bodyweight: load = .bodyweight
        }
        return PrescribedSet(id: id, setIndex: index, kind: kind,
                             repTarget: repTarget, load: load,
                             targetRPE: Double(rpeText),
                             restSeconds: Int(restText))
    }
}
