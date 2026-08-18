import SwiftUI
import CadenceCore
import CadenceFeatures

/// Compact Home presentation for the coach's selected workout of the day.
struct HomeCoachRecommendationCard: View {
    let recommendation: CoachSession
    let onStart: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 2)
            Text("Suggested Workout")
                .font(.subheadline.weight(.semibold))
            Text("Selected for today based on your recent training and recovery.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(recommendation.title)
                .font(.headline)
                .accessibilityIdentifier("home.suggestedWorkout.title")

            Text("Why this workout").font(.subheadline.weight(.semibold))
            Text(recommendation.subtitle.isEmpty ? "It matches today's recommended training load." : recommendation.subtitle)
                .font(.caption).foregroundStyle(.secondary)
            previewDetails
            ForEach(recommendation.citationIds.compactMap { CitationRegistry.citation(forId: $0) }, id: \.id) { citation in
                CitationLink(citation: citation, compact: true)
            }
            CadenceActionButton(title: "Do Coach's Workout",
                                systemImage: "play.fill",
                                action: onStart)
                .accessibilityIdentifier("home.coachRecommendation.start")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("home.coachRecommendation")
    }

    @ViewBuilder
    private var previewDetails: some View {
        if let exercises = recommendation.exercises, !exercises.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(exercises.prefix(6).enumerated()), id: \.offset) { _, exercise in
                    HStack(spacing: 6) {
                        Label(exercise.name, systemImage: "dumbbell")
                        Spacer(minLength: 4)
                        if let loadKg = exercise.loadKg, loadKg > 0 {
                            Text(Format.weight(loadKg, unit: settings.unit, decimals: 0))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
                if exercises.count > 6 {
                    Text("+\(exercises.count - 6) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let minutes = recommendation.durationMinutes {
            Text("About \(minutes) minutes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
