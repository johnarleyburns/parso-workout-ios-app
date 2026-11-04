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
                Text(SuggestedWorkoutPresenter.choosingAPlan)
                ForEach(SuggestedWorkoutStyle.allCases, id: \.self) { style in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.displayName).font(.subheadline.weight(.semibold))
                        Text(style.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("suggestedWorkout.about.style.\(style.rawValue)")
                }
            }
            Section("Scientific backing") {
                CoachSourcesLink(citationIds: SuggestedWorkoutPresenter.citationIDs,
                                 identifier: "suggestedWorkout.about.science")
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
