import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures

/// P1 — Controls (swipe right): Pause/Resume, Finish (→ review), Water Lock, Partners; Discard.
struct WatchStrengthControlsPage: View {
    let model: WatchStrengthFlowModel
    let onFinish: () -> Void
    let onPartners: () -> Void
    @Environment(WatchWorkoutManager.self) private var watchManager
    @State private var confirmDiscard = false

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Duration.seconds(watchManager.elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(WatchTone.accent)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    tile(watchManager.isPaused ? "Resume" : "Pause",
                         systemImage: watchManager.isPaused ? "play.fill" : "pause.fill",
                         identifier: "watchStrength.pause") {
                        WatchHaptics.tap()
                        watchManager.togglePause()
                    }
                    tile("Finish", systemImage: "checkmark", tint: .red, identifier: "watchStrength.finish", action: onFinish)
                    tile("Water Lock", systemImage: "drop.fill", identifier: "watchStrength.waterLock") {
                        WKInterfaceDevice.current().enableWaterLock()
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
            Text(watchManager.currentBPM.map { "\(Int($0))" } ?? "--")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchTone.heart)
                .accessibilityLabel(Text("Heart rate \(watchManager.currentBPM.map { "\(Int($0))" } ?? "unknown") beats per minute"))
            Text("BPM").font(.caption2).foregroundStyle(.secondary)
            if !isLuminanceReduced {
                Text(Duration.seconds(watchManager.elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                    .font(.footnote.monospacedDigit())
                (watchManager.hrSource == .bluetooth ? Text("Chest strap") : Text("Wrist sensor"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("watchStrength.heart")
    }
}
