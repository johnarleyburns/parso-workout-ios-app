import SwiftUI
import CadenceCore
import CadenceFeatures

struct AboutSuggestedWorkoutsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("How suggestions work") {
                ForEach(SuggestedWorkoutPresenter.aboutSteps, id: \.self) { step in
                    Text(step)
                }
            }
            Section("Algorithm pseudocode") {
                ForEach(SuggestedWorkoutPresenter.pseudocode, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            Section("Choosing a plan") {
                Text("Minimum aims for 4 sets per muscle, Medium for 8, and Maximal for 12. Each plan has a 20, 30, or 40 total-set safety cap, so a capped plan can still show remaining gaps.")
            }
            Section("Scientific backing") {
                ForEach(SuggestedWorkoutPresenter.citationIDs, id: \.self) { id in
                    if let citation = CitationRegistry.citation(forId: id) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(citation.title).font(.caption)
                            CitationLink(citation: citation, identifier: "suggestedWorkout.about.science.\(id)")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("suggestedWorkout.about.science.\(id)")
                    }
                }
            }
        }
        .navigationTitle("About suggested workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .accessibilityIdentifier("suggestedWorkout.aboutSheet")
    }
}
