import SwiftUI
import WidgetKit
import CadenceCore
import CadenceFeatures

/// Watch redesign §5 R1–R2, A1 — rest you can read from the bench: a draining ring, the time,
/// heart rate, and the next set so the bar can be loaded. Double Tap starts the next set (today's
/// behaviour, kept); rest never auto-advances. Wrist down, the ring and time stay; HR hides.
struct WatchRestView: View {
    let model: WatchStrengthFlowModel
    let talk: WatchQuickTalkController

    @Environment(AppSettings.self) private var watchSettings
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var timer: Timer?
    @State private var cues = WatchIntervalCuePlayer()
    @State private var total: Int = 1
    @State private var dictation = ""

    private var remaining: Int { model.restTimer.remaining }
    private var isOver: Bool { !model.restTimer.isRunning && remaining == 0 }

    var body: some View {
        VStack(spacing: 4) {
            ring
            if let next = nextSetText {
                Text(next).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if model.plannedRestApplied && !isOver {
                Text("Planned rest").font(.caption2).foregroundStyle(WatchTone.accent)
                    .accessibilityIdentifier("watchRest.planned")
            }
            if !isLuminanceReduced { controls }
        }
        .padding(.horizontal, 4)
        .navigationTitle("Rest")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            total = max(1, remaining)
            publishWidgetState()
            reloadWidget()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    let wasRunning = model.restTimer.isRunning
                    model.restTimer.tick()
                    publishWidgetState()
                    if wasRunning, !model.restTimer.isRunning, model.restTimer.remaining == 0 {
                        cues.restComplete(soundsEnabled: watchSettings.workoutSounds)
                        WatchWorkoutVoiceCoach.shared.speak(.restComplete, enabled: watchSettings.spokenCues)
                        WatchHaptics.success()
                    }
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            CadenceWatchWidgetStore.save(CadenceWatchWidgetState(workoutTitle: model.session?.title ?? "Workout"))
            reloadWidget()
            cues.stop()
        }
    }

    private var ring: some View {
        let fraction = isOver ? 1 : Double(remaining) / Double(max(total, remaining, 1))
        return ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 7)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(WatchTone.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            VStack(spacing: 2) {
                if isOver {
                    Text("Lift!").font(.title2.weight(.bold))
                } else if let ends = model.restTimer.endsAt {
                    Text(timerInterval: Date()...max(Date(), ends), countsDown: true)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .monospacedDigit()
                } else {
                    Text(format(remaining)).font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                }
                if !isLuminanceReduced {
                    Label(watchManager.currentBPM.map { "\(Int($0))" } ?? "--", systemImage: "heart.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WatchTone.heart)
                        .accessibilityLabel(Text("Heart rate \(watchManager.currentBPM.map { "\(Int($0))" } ?? "unknown")"))
                }
            }
        }
        .frame(width: 112, height: 112)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOver ? Text("Rest over") : Text("Rest, \(format(remaining)) left"))
    }

    @ViewBuilder
    private var controls: some View {
        if isOver {
            Button("Start set") { startNext() }
                .buttonStyle(WatchPillStyle(kind: .primary))
                .handGestureShortcut(.primaryAction)
                .accessibilityIdentifier("watchRest.nextSet")
        } else {
            HStack(spacing: 6) {
                Button("+30") {
                    WatchHaptics.tap()
                    model.addRestTime(30)
                    total += 30
                    publishWidgetState()
                    reloadWidget()
                }
                .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                .accessibilityLabel(Text("Add 30 seconds"))
                if talk.isPhoneReachable {
                    Button { talk.startListening() } label: { Image(systemName: "mic.fill") }
                        .buttonStyle(WatchPillStyle(kind: .light, small: true))
                        .accessibilityLabel(Text("Talk"))
                        .accessibilityIdentifier("watchRest.talk")
                        .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in talk.finishListening() })
                } else {
                    TextField("Dictate", text: $dictation)
                        .onSubmit {
                            let text = dictation
                            dictation = ""
                            talk.handle(transcript: text, source: .dictation)
                        }
                        .accessibilityIdentifier("watchRest.dictate")
                }
                Button("Next set") { startNext() }
                    .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                    .handGestureShortcut(.primaryAction)
                    .accessibilityIdentifier("watchRest.nextSet")
            }
        }
    }

    private var nextSetText: String? {
        guard let name = model.currentExerciseName else { return nil }
        return String(localized: "Next · \(name)")
    }

    private func startNext() {
        WatchHaptics.tap()
        timer?.invalidate()
        model.finishRest()
    }

    private func publishWidgetState() {
        CadenceWatchWidgetStore.save(CadenceWatchWidgetState(
            workoutTitle: model.session?.title ?? "Workout",
            restEndsAt: model.restTimer.endsAt,
            restTotalSeconds: total,
            nextSet: nextSetText))
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "CadenceWatchSmartStackWidget")
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
