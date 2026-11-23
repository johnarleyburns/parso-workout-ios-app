import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// P1 — Summary (swipe right): live elapsed time, sets/cardio rings, and one
/// bottom toolbar (pause, guarded finish, partners).
struct WatchStrengthControlsPage: View {
    let model: WatchStrengthFlowModel
    let onFinish: () -> Void
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(AppSettings.self) private var watchSettings
    @State private var confirmDiscard = false
    @State private var confirmFinish = false
    @State private var showingPartners = false

    var body: some View {
        GeometryReader { proxy in
            let summary = liveSummary
            let side = min(proxy.size.width * 0.82, proxy.size.height * 0.48)
            let lineWidth = max(7, side * 0.10)
            VStack(spacing: 4) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Duration.seconds(watchManager.effectiveElapsed).formatted(.time(pattern: .hourMinuteSecond)))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(WatchTone.accent)
                }
                if watchManager.isPaused, let copy = watchManager.strengthPause.statusCopy {
                    Text(copy)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(.top, CGFloat(WatchStrengthControlsPresentation.pauseReasonTopPadding))
                        .accessibilityIdentifier("watchStrength.pauseReason")
                }
                ZStack {
                    ring(progress: summary.setsProgress, tint: WatchTone.accent,
                         diameter: side, lineWidth: lineWidth)
                    ring(progress: summary.cardioProgress, tint: WatchTone.cardio,
                         diameter: side * 0.62, lineWidth: lineWidth)
                }
                .frame(width: side, height: side)
                .accessibilityHidden(true)
                HStack(spacing: 6) {
                    legend("Sets", value: setsText(summary), tint: WatchTone.accent)
                    legend("Cardio", value: "\(summary.cardioMinutes) min", tint: WatchTone.cardio)
                }
                Spacer(minLength: 0)
                Button("Discard Workout", role: .destructive) { confirmDiscard = true }
                    .font(.footnote)
                    .accessibilityIdentifier("watchStrength.deleteWorkout")
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(LocalizedStringKey(WatchStrengthControlsPresentation.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 8) {
                    Button {
                        WatchHaptics.tap()
                        watchManager.recordStrengthMeaningfulActivity(watchManager.isPaused ? .userResume : .userPause)
                        watchManager.userToggleStrengthPause(origin: .userControl)
                    } label: {
                        Image(systemName: watchManager.isPaused ? "play.fill" : "pause.fill")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(watchManager.isPaused ? Text("Resume") : Text("Pause"))
                    .accessibilityIdentifier("watchStrength.pause")

                    Spacer(minLength: 0)

                    Button {
                        confirmFinish = true
                    } label: {
                        Image(systemName: WatchPhasePresentation.endSystemImage)
                            .font(.headline.weight(.bold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(Text("Finish"))
                    .accessibilityIdentifier("watchStrength.finish")

                    Spacer(minLength: 0)

                    Button {
                        showingPartners = true
                    } label: {
                        Image(systemName: "person.2.fill")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(Text("Partners"))
                    .accessibilityIdentifier("watchStrength.partners")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog(
            LocalizedStringKey(WatchStrengthControlsPresentation.finishConfirmationTitle),
            isPresented: $confirmFinish,
            titleVisibility: .visible
        ) {
            Button(LocalizedStringKey(WatchStrengthControlsPresentation.finishCoolDownTitle)) {
                onFinish()
            }
            .accessibilityIdentifier("watchStrength.finish.coolDown")
            Button(LocalizedStringKey(WatchStrengthControlsPresentation.finishCancelTitle),
                   role: .cancel) {}
                .accessibilityIdentifier("watchStrength.finish.cancel")
        }
        .sheet(isPresented: $showingPartners) {
            NavigationStack { WatchPartnersView(model: model) }
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

    private var liveSummary: WatchLiveSummaryPresentation {
        let cardio = WatchStrengthHRCoverage.summary(
            samples: watchManager.currentHRSamplesForSummary,
            duration: watchManager.effectiveElapsed,
            profile: watchSettings.resolvedCardioIntensityProfile)
        return WatchLiveSummaryPresentation.make(
            setsCompleted: model.setCount,
            setsPlanned: model.plannedWorkingSetTotal,
            cardioMinutes: cardio?.moderateEquivalentMinutes ?? 0)
    }

    private func setsText(_ summary: WatchLiveSummaryPresentation) -> String {
        summary.setsPlanned > 0
            ? "\(summary.setsCompleted)/\(summary.setsPlanned)"
            : "\(summary.setsCompleted)"
    }

    private func ring(progress: Double, tint: Color, diameter: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle().trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private func legend(_ title: LocalizedStringKey, value: String, tint: Color) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(tint)
            Text(value).font(.system(.caption, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title) + Text(verbatim: ": \(value)"))
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
