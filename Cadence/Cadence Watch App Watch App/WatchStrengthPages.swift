import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// P1 — Controls (swipe right): Pause/Resume, Finish (→ review), Water Lock, Partners; Discard.
struct WatchStrengthControlsPage: View {
    let model: WatchStrengthFlowModel
    let onFinish: () -> Void
    let onPartners: () -> Void
    @Environment(WatchWorkoutManager.self) private var watchManager
    @State private var confirmDiscard = false
    /// Self-tracked feedback only: WatchKit exposes no reactive notification for
    /// the water-lock toggle, so this reflects "we just asked the system to
    /// engage it," not a live readback of the actual lock state.
    @State private var waterLockEngaged = false

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Duration.seconds(watchManager.effectiveElapsed).formatted(.time(pattern: .hourMinuteSecond)))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(WatchTone.accent)
                }
                // Fixed-height reservation: this row was being inserted/removed as
                // the pause-reason text appeared/disappeared, shifting the tile
                // grid below it. Always occupy the space; only the text itself is
                // conditional.
                Text(watchManager.isPaused ? (watchManager.strengthPause.statusCopy ?? "") : "")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 28)
                    .accessibilityIdentifier("watchStrength.pauseReason")
                    .accessibilityHidden(!watchManager.isPaused || watchManager.strengthPause.statusCopy == nil)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    tile(watchManager.isPaused ? "Resume" : "Pause",
                         systemImage: watchManager.isPaused ? "play.fill" : "pause.fill",
                         identifier: "watchStrength.pause") {
                        WatchHaptics.tap()
                        watchManager.recordStrengthMeaningfulActivity(watchManager.isPaused ? .userResume : .userPause)
                        watchManager.userToggleStrengthPause(origin: .userControl)
                    }
                    tile("Finish", systemImage: "checkmark", tint: .red, identifier: "watchStrength.finish", action: onFinish)
                    tile(waterLockEngaged ? "Locked" : "Water Lock",
                         systemImage: waterLockEngaged ? "drop.fill" : "drop",
                         identifier: "watchStrength.waterLock") {
                        if watchManager.enableWaterLock() {
                            WatchHaptics.tap()
                            waterLockEngaged = true
                        }
                    }
                    tile("Partners", systemImage: "person.2.fill", identifier: "watchStrength.partners", action: onPartners)
                }
                Button("Discard Workout", role: .destructive) { confirmDiscard = true }
                    .font(.footnote)
                    .accessibilityIdentifier("watchStrength.deleteWorkout")
            }
            .padding(.horizontal, 2)
        }
        .alert("Delete Workout?", isPresented: $confirmDiscard) {
            Button("Delete", role: .destructive) {
                WatchHaptics.delete()
                model.cancel()
            }
            .accessibilityIdentifier("watchStrength.deleteWorkout.confirm")
            Button("Keep Workout", role: .cancel) {}
                .accessibilityIdentifier("watchStrength.deleteWorkout.cancel")
        } message: {
            Text("This removes the workout and all sets logged on the watch.")
        }
    }

    private func tile(_ title: LocalizedStringKey, systemImage: String, tint: Color = .white,
                      identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(tint == .red ? Color.red : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(RoundedRectangle(cornerRadius: 14).fill(tint == .red ? Color.red.opacity(0.18) : WatchTone.surface))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// P4 — Heart: live BPM, zone, elapsed, and which sensor it comes from.
struct WatchHeartPage: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(spacing: 4) {
            Text(LiveHeartRateDisplay(bpm: watchManager.currentBPM).valueText)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchTone.heart)
                .accessibilityLabel(Text("Heart rate \(LiveHeartRateDisplay(bpm: watchManager.currentBPM).valueText) beats per minute"))
            Text("BPM").font(.caption2).foregroundStyle(.secondary)
            if !isLuminanceReduced {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Duration.seconds(watchManager.effectiveElapsed).formatted(.time(pattern: .hourMinuteSecond)))
                        .font(.footnote.monospacedDigit())
                }
                (watchManager.hrSource == .bluetooth ? Text("Chest strap") : Text("Wrist sensor"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("watchStrength.heart")
    }
}
