import SwiftUI
import SwiftData
import ImageIO
import CadenceCore
import CadenceFeatures

struct WatchAddExerciseView: View {
    let model: WatchStrengthFlowModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var recent: [Exercise] = []
    @State private var selectedBodyPart: BodyPart?
    @State private var selectedExercise: Exercise?
    @State private var query = ""

    init(model: WatchStrengthFlowModel) {
        self.model = model
        _exercises = Query(sort: \Exercise.name)
    }

    var body: some View {
        Group {
            if let selectedExercise {
                preview(selectedExercise)
            } else {
                picker
            }
        }
        .navigationTitle(selectedExercise?.name ?? selectedBodyPart?.displayName ?? "Add Exercise")
        .task { loadRecent() }
    }

    private var picker: some View {
        List {
            Section {
                TextField("Search", text: $query)
                    .accessibilityIdentifier("watchAddExercise.search")
            }

            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Matches") {
                    ForEach(WatchExerciseSelection.search(query, exercises: exercises), id: \.persistentModelID) { exercise in
                        exerciseButton(exercise)
                    }
                }
            } else if let selectedBodyPart {
                Section {
                    Button {
                        WatchHaptics.tap()
                        self.selectedBodyPart = nil
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                }
                Section(selectedBodyPart.displayName) {
                    ForEach(WatchExerciseSelection.fullList(for: selectedBodyPart, exercises: exercises), id: \.self) { name in
                        if let exercise = exercise(named: name) {
                            exerciseButton(exercise)
                        }
                    }
                }
            } else {
                ForEach(WatchExerciseSelection.defaultSections(exercises: exercises, recent: recent)) { section in
                    Section(section.title) {
                        ForEach(section.exerciseNames, id: \.self) { name in
                            if let exercise = exercise(named: name) {
                                exerciseButton(exercise)
                            }
                        }
                        if let part = section.otherBodyPart {
                            Button {
                                WatchHaptics.tap()
                                selectedBodyPart = part
                            } label: {
                                Label("Other...", systemImage: "ellipsis.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func preview(_ exercise: Exercise) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let imageURLs = ExerciseLibrary.imageURLs(forImageName: exercise.imageName)
                if !imageURLs.isEmpty {
                    ForEach(imageURLs, id: \.self) { url in
                        exerciseImage(url)
                    }
                }

                if !exercise.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(exercise.instructions.prefix(4).enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step)")
                                .font(.caption2)
                        }
                    }
                } else {
                    Text(exercise.displayFacetTags.prefix(3).joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        WatchHaptics.tap()
                        selectedExercise = nil
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("watchAddExercise.previewBack")

                    Button {
                        WatchHaptics.success()
                        model.addExercise(named: exercise.name)
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("watchAddExercise.previewAdd")
                }
            }
            .padding()
        }
    }

    private func exerciseButton(_ exercise: Exercise) -> some View {
        Button {
            WatchHaptics.tap()
            selectedExercise = exercise
        } label: {
            Text(exercise.name)
                .lineLimit(2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watchAddExercise.row.\(exercise.name)")
    }

    @ViewBuilder
    private func exerciseImage(_ url: URL) -> some View {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            Image(decorative: image, scale: 1, orientation: .up)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.18))
                .frame(height: 96)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func exercise(named name: String) -> Exercise? {
        exercises.first {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
    }

    private func loadRecent() {
        recent = (try? WorkoutRepository.recentlyUsedExercises(context, limit: 12)) ?? []
    }
}
