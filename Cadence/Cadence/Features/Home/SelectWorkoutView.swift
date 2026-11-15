import SwiftUI
import CadenceCore
import CadenceFeatures

/// Compatibility wrapper for the existing sheet-owned start boundary. The
/// visible Today entry now lives in `StartWorkoutView`; this wrapper keeps the
/// sheet dismissal and Home callbacks in one place.
struct SelectWorkoutView: View {
    let onEditorStart: (EditablePlan) -> Void
    let onCreateDraft: () -> Void
    let onLogWorkout: () -> Void
    let onStartCardio: (WorkoutType) -> Void
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    var recentCardioTypes: [WorkoutType] = []
    /// Home's cached weekly cardio credit, forwarded to the Cardio picker.
    let weeklyCardioCredit: CardioWeeklyCreditDisplay
    var onFillGaps: (() -> Void)? = nil
    var onSuggestCardio: (() -> Void)? = nil
    var inline = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if inline {
            NavigationLink {
                StartWorkoutView(
                    onEditorStart: onEditorStart,
                    onCreateDraft: onCreateDraft,
                    onLogWorkout: onLogWorkout,
                    onStartCardio: onStartCardio,
                    onOtherCardio: onOtherCardio,
                    recentCardioTypes: recentCardioTypes,
                    weeklyCardioCredit: weeklyCardioCredit,
                    onFillGaps: onFillGaps,
                    onSuggestCardio: onSuggestCardio)
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
                    onEditorStart: onEditorStart,
                    onCreateDraft: onCreateDraft,
                    onLogWorkout: onLogWorkout,
                    onStartCardio: onStartCardio,
                    onOtherCardio: onOtherCardio,
                    recentCardioTypes: recentCardioTypes,
                    weeklyCardioCredit: weeklyCardioCredit,
                    onFillGaps: onFillGaps,
                    onSuggestCardio: onSuggestCardio)
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
