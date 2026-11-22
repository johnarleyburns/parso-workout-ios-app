import SwiftUI
import CadenceWorkoutFeatures

/// The coach's auditable reasoning for a suggested Lift. Everything shown here
/// comes from the shared rationale that traveled with the suggestion; the Watch
/// never invents or re-derives the explanation.
struct WatchLiftWhyView: View {
    let presentation: WatchLiftWhyPresentation
    var citationIDs: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(presentation.title))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(presentation.whyWorkout)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("watchLift.why.workout")
                ForEach(presentation.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.exerciseName.localizedExerciseName)
                            .font(.footnote.weight(.semibold))
                        Text(exercise.whyExercise)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(exercise.whySetRep)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !citationIDs.isEmpty {
                    WatchCoachLineView(line: WatchCoachLine(text: "Workout sources",
                                                            citationIDs: citationIDs))
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(LocalizedStringKey(presentation.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
