import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct WatchAddExerciseView: View {
    let model: WatchStrengthFlowModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var recent: [Exercise] = []
    @State private var selectedBodyPart: BodyPart?

    init(model: WatchStrengthFlowModel) {
        self.model = model
        _exercises = Query(sort: \Exercise.name)
    }

    var body: some View {
        List {
            if let selectedBodyPart {
                Section {
                    Button {
                        self.selectedBodyPart = nil
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                }
                Section(selectedBodyPart.displayName) {
                    ForEach(WatchExerciseSelection.fullList(for: selectedBodyPart, exercises: exercises), id: \.self) { name in
                        exerciseButton(name)
                    }
                }
            } else {
                ForEach(WatchExerciseSelection.defaultSections(exercises: exercises, recent: recent)) { section in
                    Section(section.title) {
                        ForEach(section.exerciseNames, id: \.self) { name in
                            exerciseButton(name)
                        }
                        if let part = section.otherBodyPart {
                            Button {
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
        .navigationTitle(selectedBodyPart?.displayName ?? "Add Exercise")
        .task { loadRecent() }
    }

    private func exerciseButton(_ name: String) -> some View {
        Button {
            model.addExercise(named: name)
        } label: {
            Text(name)
                .lineLimit(2)
        }
        .buttonStyle(.plain)
    }

    private func loadRecent() {
        recent = (try? WorkoutRepository.recentlyUsedExercises(context, limit: 12)) ?? []
    }
}
