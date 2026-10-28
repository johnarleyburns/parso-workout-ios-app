import SwiftUI
import CadenceFeatures

/// The shared in-workout control pair (field-testing Round 4 A1/A2): a big
/// Pause/Resume toggle and a big End button that routes through an
/// "Are you sure?" confirm. Every in-workout screen (strength, cardio, interval)
/// uses this instead of a bespoke `HStack` so the behavior is uniform — large
/// hit targets (≥56 pt), high contrast, and confirm-before-end.
///
/// `idPrefix` keeps each screen's existing accessibility ids (`outdoor.pause`,
/// `record.end`, …) so the FR2 UI suite keeps navigating; the confirm dialog's
/// buttons always use the shared `workout.endConfirm` / `workout.endCancel` ids.
struct WorkoutControlBar: View {
    let isPaused: Bool
    let onPauseToggle: () -> Void
    /// Called only AFTER the user confirms End (or immediately when
    /// `confirmEnd == false`).
    let onEnd: () -> Void
    /// When set, the End confirmation offers "Cool down, then finish" (it is no
    /// longer a persistent row); it runs a guided cool-down timer that finishes
    /// the workout on completion.
    /// Strength passes this; cardio/interval (which bake in their own
    /// cool-down) leave it nil.
    var onCoolDown: (() -> Void)? = nil

    /// Prefixes the Pause/End accessibility ids (e.g. `outdoor` → `outdoor.pause`,
    /// `outdoor.end`). Defaults to the generic `workout`.
    var idPrefix: String = "workout"
    var endTitle: String = "End"
    var confirmTitle: String = String(localized: "End workout?")
    var confirmMessage: String? = nil
    /// When false, End fires immediately with no confirm — used where there is
    /// nothing to lose (e.g. the pre-workout countdown's discard).
    var confirmEnd: Bool = true
    var endTint: Color = .red
    /// Tint for the Pause/Resume button. nil uses the inherited tint (so the
    /// interval screen's translucent style is preserved).
    var pauseTint: Color? = nil

    @State private var confirming = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if WorkoutDockLayout.resolve(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) == .vertical {
                VStack(spacing: 12) { dockActions }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { dockActions }
                    VStack(spacing: 12) { dockActions }
                }
            }
        }
        .glassGroup(spacing: 12)
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            if let onCoolDown {
                Button("Cool down, then finish") { onCoolDown() }
                    .accessibilityIdentifier("workout.endCoolDown")
            }
            Button(endTitle, role: .destructive) { onEnd() }
                .accessibilityIdentifier("workout.endConfirm")
            Button("Keep going", role: .cancel) { }
                .accessibilityIdentifier("workout.endCancel")
        } message: {
            if let confirmMessage { Text(confirmMessage) }
        }
    }

    @ViewBuilder private var dockActions: some View {
        let pause = WorkoutDockPresenter.pauseContent(isPaused: isPaused)
        Button(action: onPauseToggle) {
            Label(LocalizedStringKey(pause.title), systemImage: pause.systemImage)
                .frame(maxWidth: .infinity, minHeight: WorkoutDockPresenter.minimumTargetHeight)
        }
        .cadenceGlassButton(tint: pauseTint)
        .accessibilityIdentifier("\(idPrefix).pause")

        Button(role: .destructive) {
            if confirmEnd { confirming = true } else { onEnd() }
        } label: {
            Label(endTitle, systemImage: WorkoutDockPresenter.endSystemImage)
                .frame(maxWidth: .infinity, minHeight: WorkoutDockPresenter.minimumTargetHeight)
        }
        .cadenceGlassButton(prominent: false, tint: endTint)
        .accessibilityIdentifier("\(idPrefix).end")
    }
}
