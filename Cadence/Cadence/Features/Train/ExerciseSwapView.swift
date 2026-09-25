import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct ExerciseSwapView: View {
    let source: Exercise
    let onPick: (Exercise) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: ExerciseTrainingType
    @State private var showSearch = false
    /// Prepared once on a background context. This used to be a computed
    /// property that prepared all ~900 exercises and re-ranked them for every
    /// training type several times per render, on the main thread.
    @State private var presenter: ExerciseSwapPresenter?
    @State private var results: [ExerciseSimilarity.Result] = []

    init(source: Exercise, onPick: @escaping (Exercise) -> Void) {
        self.source = source; self.onPick = onPick
        _selectedType = State(initialValue: source.trainingTypes.first ?? .strength)
    }

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
                    if let presenter {
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
                                Button { pick(result) } label: { row(result) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("swap.similar.\(result.candidate.name)")
                            }
                        }
                        if results.contains(where: \.borrowed) {
                            Section("Other types") {
                                ForEach(results.filter(\.borrowed)) { result in
                                    Button { pick(result) } label: { row(result) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        Section {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Finding similar exercises…").foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("swap.loading")
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
            .task(id: selectedType) { await refreshResults() }
        }
    }

    /// Prepares the candidates once, then ranks for the selected type off the
    /// main thread.
    private func refreshResults() async {
        let type = selectedType
        if presenter == nil {
            let prepared = ExerciseSwapCandidates.prepared(source)
            presenter = await ExerciseSwapCandidates.presenter(source: prepared, container: context.container)
        }
        guard let presenter else { return }
        let ranked = await Task.detached(priority: .userInitiated) { presenter.results(for: type) }.value
        guard !Task.isCancelled, type == selectedType else { return }
        results = ranked
    }

    /// The stored exercise is read only when picked.
    private func pick(_ result: ExerciseSimilarity.Result) {
        guard let id = UUID(uuidString: result.candidate.id),
              let exercise = ExerciseCatalogSnapshot.exercise(id: id, in: context) else { return }
        onPick(exercise)
        dismiss()
    }

    private func row(_ result: ExerciseSimilarity.Result) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(result.candidate.name)
                Spacer()
                Text("\(Int((result.score * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("\(result.candidate.direct.map(\.displayName).joined(separator: ", ")) · indirect: \(result.candidate.indirect.map(\.displayName).joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
