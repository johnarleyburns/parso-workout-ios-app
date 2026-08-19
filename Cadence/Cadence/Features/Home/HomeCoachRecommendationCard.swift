import SwiftUI
import CadenceCore
import CadenceFeatures

/// The suggested workout, rendered at the bottom of Home's Coach's Suggestions
/// card. Body only: field test 2026-08-18 #9 removed the divider and the
/// "Suggested Workout" blurb, and #11 moved `Do Coach's Workout` out to
/// `HomeCoachSuggestionsSection` as a sibling of the card.
struct HomeCoachRecommendationCard: View {
    let title: String
    let why: String
    let exercises: [HomeCoachSectionPresenter.ExercisePreview]
    let additionalCount: Int
    let citationIds: [String]
    let durationMinutes: Int?
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityIdentifier("home.suggestedWorkout.title")

            Text("Why this workout").font(.subheadline.weight(.semibold))
            Text(why)
                .font(.caption).foregroundStyle(.secondary)
            previewDetails
            CoachSourcesLink(citationIds: citationIds,
                             identifier: "home.coachRecommendation.science")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.coachRecommendation")
    }

    @ViewBuilder
    private var previewDetails: some View {
        if !exercises.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(exercises.enumerated()), id: \.offset) { _, exercise in
                    HStack(spacing: 6) {
                        Label(exercise.name, systemImage: "dumbbell")
                        Spacer(minLength: 4)
                        if let loadKg = exercise.loadKg, loadKg > 0 {
                            Text(Format.weight(loadKg, unit: settings.unit, decimals: 0))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else if ExerciseLoading.isBodyweight(named: exercise.name) {
                            // Bodyweight is a real prescription; an unresolved load
                            // on a loaded lift still shows nothing (field test #2).
                            Text("BW")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
                if additionalCount > 0 {
                    Text("+\(additionalCount) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let minutes = durationMinutes {
            Text("About \(minutes) minutes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
