import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct ExerciseSwapView: View {
    let source: Exercise
    let exercises: [Exercise]
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: ExerciseTrainingType
    @State private var showSearch = false

    init(source: Exercise, exercises: [Exercise], onPick: @escaping (Exercise) -> Void) {
        self.source = source; self.exercises = exercises; self.onPick = onPick
        _selectedType = State(initialValue: source.trainingTypes.first ?? .strength)
    }

    private var preparedSource: ExerciseSimilarity.Prepared { Self.prepared(source) }
    private var presenter: ExerciseSwapPresenter { ExerciseSwapPresenter(source: preparedSource, candidates: exercises.map(Self.prepared)) }
    private var results: [ExerciseSimilarity.Result] { presenter.results(for: selectedType) }
    private var directLabel: String { source.directMuscles.map(\.displayName).joined(separator: ", ") }

    var body: some View {
        if showSearch {
            ExercisePickerView(action: .swap, source: nil, onPick: onPick)
        } else {
            NavigationStack {
                List {
                    Section {
                        Text("Swap with a similar exercise").font(.headline)
                        Text("Replacing: \(source.name)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(presenter.availableTypes, id: \.self) { type in
                                    Button(type.displayName) { selectedType = type }
                                        .buttonStyle(.borderedProminent)
                                        .tint(selectedType == type ? .accentColor : .gray)
                                        .accessibilityIdentifier("swap.type.\(type.rawValue)")
                                }
                            }
                        }
                    }
                    Section("Most similar") {
                        ForEach(results.filter { !$0.borrowed }) { result in
                            if let exercise = exercises.first(where: { $0.id.uuidString == result.candidate.id }) {
                                Button { onPick(exercise); dismiss() } label: { row(result, exercise) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("swap.similar.\(exercise.name)")
                            }
                        }
                    }
                    if results.contains(where: \.borrowed) {
                        Section("Other types") {
                            ForEach(results.filter(\.borrowed)) { result in
                                if let exercise = exercises.first(where: { $0.id.uuidString == result.candidate.id }) {
                                    Button { onPick(exercise); dismiss() } label: { row(result, exercise) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    Section {
                        Button("Search all exercises", systemImage: "magnifyingglass") { showSearch = true }
                            .accessibilityIdentifier("swap.searchAll")
                    }
                }
                .navigationTitle("Swap Exercise")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }
    }

    private func row(_ result: ExerciseSimilarity.Result, _ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(exercise.name)
                Spacer()
                Text("\(Int((result.score * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("\(result.candidate.direct.map(\.displayName).joined(separator: ", ")) · indirect: \(result.candidate.indirect.map(\.displayName).joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    static func prepared(_ exercise: Exercise) -> ExerciseSimilarity.Prepared {
        let direct = Set(exercise.directMuscles.isEmpty ? MuscleGroup.canonicalize(exercise.primaryMuscles) : exercise.directMuscles)
        let indirect = Set(exercise.indirectMuscles.isEmpty ? MuscleGroup.canonicalize(exercise.secondaryMuscles) : exercise.indirectMuscles)
        return ExerciseSimilarity.Prepared(id: exercise.id.uuidString, name: exercise.name, direct: direct, indirect: indirect,
                                           patterns: Set(exercise.movementPatternIDs), mechanics: exercise.mechanicsValue,
                                           force: exercise.forceValue, equipment: exercise.equipmentValue,
                                           modalities: Set(exercise.modalities), trainingTypes: Set(exercise.trainingTypes),
                                           volumeEligible: exercise.volumeEligible)
    }
}
