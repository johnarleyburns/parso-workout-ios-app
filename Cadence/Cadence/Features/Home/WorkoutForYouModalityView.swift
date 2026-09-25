import SwiftUI
import CadenceCore
import CadenceFeatures

struct WorkoutForYouModalityView: View {
    let onSelect: (SuggestedWorkoutModality) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What would you like to do?")
                .font(.headline)
            Text("Start Workout uses your history and weekly needs to prepare one session for you to review before starting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(SuggestedWorkoutModality.allCases) { modality in
                Button {
                    onSelect(modality)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: modality.symbol)
                            .font(.title3)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(modality.displayName)
                                .font(.headline)
                            Text(modality == .strength
                                 ? "Muscle-group gaps and your exercise history"
                                 : "Recent cardio, weekly minutes, and intensity")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: CGFloat(LayoutMetrics.actionButtonHeight), alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .tint(modality == .strength ? .green : .blue)
                .accessibilityIdentifier("workoutForYou.\(modality.rawValue)")
            }

            Spacer()
        }
        .padding(CGFloat(LayoutMetrics.pagePadding))
        .navigationTitle("Start Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("workoutForYou.cancel")
            }
        }
    }
}

struct SuggestedCardioPreviewView: View {
    let suggestion: CardioSuggestion
    let onStart: (CardioSuggestion) -> Void
    let onSchedule: (CardioSuggestion) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(suggestion.type.displayName, systemImage: suggestion.type.symbol)
                    .font(.title2.weight(.bold))
                HStack(spacing: 12) {
                    metric("Duration", "\(suggestion.durationMinutes) min")
                    metric("Intensity", suggestion.intensity.displayName)
                }
                HStack {
                    Label(suggestion.indoor ? "Indoor by default" : "Outdoor by default",
                          systemImage: suggestion.indoor ? "house.fill" : "location.fill")
                    Spacer()
                    Text("Change before starting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

                Text("Why this workout")
                    .font(.headline)
                Text(suggestion.rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let citation = suggestion.citationIDs.first.flatMap(CitationRegistry.citation(forId:)) {
                    CitationLink(citation: citation, context: "How this cardio suggestion is selected", compact: true)
                }

                Button {
                    onStart(suggestion)
                    dismiss()
                } label: {
                    Label("Start \(suggestion.type.displayName)", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .accessibilityIdentifier("suggestedCardio.start")

                Button {
                    onSchedule(suggestion)
                    dismiss()
                } label: {
                    Label("Schedule \(suggestion.type.displayName)", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .accessibilityIdentifier("suggestedCardio.schedule")

                Button("Cancel") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("suggestedCardio.cancel")
            }
            .padding(CGFloat(LayoutMetrics.pagePadding))
        }
        .navigationTitle("Cardio for You")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("suggestedCardio.preview")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
