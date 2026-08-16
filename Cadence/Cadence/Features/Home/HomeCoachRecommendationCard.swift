import SwiftUI
import CadenceCore

/// Compact Home presentation for the coach's current gap-closing workout.
/// Preview and start always use the same immutable CoachSession value.
struct HomeCoachRecommendationCard: View {
    let recommendation: CoachSession
    let isPreviewed: Bool
    let onPreview: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 2)
            Text("Suggested Workout")
                .font(.subheadline.weight(.semibold))
            Text("Coach created a Workout created to close gaps for this week")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(recommendation.title)
                .font(.headline)
                .accessibilityIdentifier("home.suggestedWorkout.title")

            if isPreviewed {
                previewDetails
                Button(action: onStart) {
                    Label("Start Workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("home.coachRecommendation.start")
            } else {
                Button(action: onPreview) {
                    Label("Preview Workout", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("home.coachRecommendation.preview")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("home.coachRecommendation")
    }

    @ViewBuilder
    private var previewDetails: some View {
        if let exercises = recommendation.exercises, !exercises.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(exercises.prefix(6).enumerated()), id: \.offset) { _, exercise in
                    Label(exercise.name, systemImage: "dumbbell")
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
