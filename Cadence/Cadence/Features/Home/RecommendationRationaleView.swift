import SwiftUI
import CadenceCore

/// Detailed recommendation reasoning is available on demand so the plan
/// remains scannable while every selection remains auditable.
struct RecommendationRationaleDisclosure: View {
    let rationale: SuggestedWorkoutRationale
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text(rationale.whyWorkout)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(rationale.exercises, id: \.exerciseName) { exercise in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(exercise.whyExercise)
                            Text(exercise.whySetRep)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    } label: {
                        Text("Why this exercise: \(exercise.exerciseName)")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("WHY: this workout", systemImage: "questionmark.circle")
                .font(.subheadline.weight(.semibold))
        }
        .tint(CadenceTheme.link)
        .accessibilityIdentifier("recommendationRationale")
    }
}

struct RecommendationRationaleSheet: View {
    let rationale: SuggestedWorkoutRationale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Why this workout")
                        .font(.title3.weight(.bold))
                    Text(rationale.whyWorkout)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(rationale.exercises, id: \.exerciseName) { exercise in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Why this exercise: \(exercise.exerciseName)")
                                .font(.headline)
                            Text(exercise.whyExercise)
                            Text(exercise.whySetRep)
                        }
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Recommendation WHY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
