import SwiftUI
import CadenceCore
import CadenceFeatures

/// Compatibility wrapper for the existing sheet-owned start boundary. The
/// visible Today entry now lives in `StartWorkoutView`; this wrapper keeps the
/// sheet dismissal and Home callbacks in one place.
struct SelectWorkoutView: View {
    let onSuggestedWorkout: (SuggestedWorkoutModality) -> Void
    let onEditorStart: (EditablePlan) -> Void
    let onScheduleStrength: () -> Void
    let onLogWorkout: () -> Void
    let onStartCardio: (WorkoutType) -> Void
    let onScheduleCardio: (WorkoutType) -> Void
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    var recentCardioTypes: [WorkoutType] = []
    var inline = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if inline {
            NavigationLink {
                StartWorkoutView(
                    onSuggestedWorkout: onSuggestedWorkout,
                    onEditorStart: onEditorStart,
                    onScheduleStrength: onScheduleStrength,
                    onLogWorkout: onLogWorkout,
                    onStartCardio: onStartCardio,
                    onScheduleCardio: onScheduleCardio,
                    onOtherCardio: onOtherCardio,
                    recentCardioTypes: recentCardioTypes)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill").font(.headline)
                    Text("Start Workout").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline).opacity(0.8)
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(CadenceTheme.accent)
            .accessibilityIdentifier("selectWorkout.startWorkout")
        } else {
            NavigationStack {
                StartWorkoutView(
                    onSuggestedWorkout: onSuggestedWorkout,
                    onEditorStart: onEditorStart,
                    onScheduleStrength: onScheduleStrength,
                    onLogWorkout: onLogWorkout,
                    onStartCardio: onStartCardio,
                    onScheduleCardio: onScheduleCardio,
                    onOtherCardio: onOtherCardio,
                    recentCardioTypes: recentCardioTypes)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                                .accessibilityIdentifier("selectWorkout.cancel")
                        }
                    }
            }
        }
    }
}
