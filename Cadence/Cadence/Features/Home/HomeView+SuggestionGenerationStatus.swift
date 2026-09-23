import SwiftUI

extension HomeView {
    @ViewBuilder
    var suggestionGenerationStatus: some View {
        if suggestedWorkoutCalculating || suggestedCardioCalculating {
            HStack(spacing: 10) {
                ProgressView()
                Text(suggestedCardioCalculating
                     ? "Building your cardio workout…"
                     : "Building your strength workout…")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("Cancel") {
                    if suggestedCardioCalculating {
                        cancelSuggestedCardioGeneration()
                    } else {
                        cancelSuggestedWorkoutGeneration()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("suggestedWorkout.cancel")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 8, y: 3)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("suggestedWorkout.calculating")
        }
    }
}
