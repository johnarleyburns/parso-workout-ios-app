import SwiftUI
import Combine
import CadenceCore

/// A guided warm-up / cool-down timer shown over a workout (feedback batch 4).
/// Generalizes the get-ready countdown: the phase name, +1 minute,
/// Pause/Resume, and the phase's finish action (Skip for warm-up, End for
/// cool-down). When the timer reaches zero — or the user taps that finish
/// action — `onFinish` fires (warm-up → opens the session; cool-down →
/// finishes it). Warm-up promotes a caller-owned live metric (BPM) above a
/// smaller countdown because the phase is primarily cardio; cool-down keeps
/// the countdown as the hero.
///
/// Timing is wall-clock based via `PhaseCountdownClock`, so the countdown **keeps
/// running while the app is backgrounded** and is correct on return; it only
/// freezes when the user explicitly taps Pause. The 1 Hz timer is a display
/// refresh only.
///
/// `idPrefix` namespaces the accessibility ids ("warmup"/"cooldown") so the two
/// surfaces are individually addressable in UI tests:
/// `<prefix>.remaining`, `<prefix>.pause`, `<prefix>.skip`.
///
/// `onFinish` reports the **actual seconds consumed** (configured length minus what
/// was left when it ended) so history can show the real warm-up/cool-down time —
/// e.g. skipping a 10:00 cool-down at 3:00 reports 180 (feedback batch 6).
struct GuidedPhaseOverlay: View {
    /// Warm-up is primarily a cardio task, so it promotes the live metric and
    /// demotes the countdown. Cool-down keeps the timer as the hero.
    enum Emphasis: Equatable {
        case timer
        case liveMetric
    }

    let title: String
    let minutes: Int
    var tint: Color = .green
    var idPrefix: String
    /// Play a transition bell when this phase begins (batch 7 item 9).
    var soundsEnabled: Bool = false
    var emphasis: Emphasis = .timer
    /// Warm-up's pause action is the universally understood glyph; cool-down
    /// keeps its label.
    var pauseShowsTitle: Bool = true
    /// The phase's second action matches the workout dock: warm-up skips ahead,
    /// cool-down ends the workout.
    var finishTitle: String = String(localized: "Skip")
    /// The phase action glyph: `chevron.forward.2` for warm-up skip, the square
    /// stop icon for cool-down End.
    var finishSystemImage: String = "stop.fill"
    var finishTint: Color = .red
    let onFinish: (_ elapsedSeconds: Int) -> Void
    let onSkip: ((_ elapsedSeconds: Int) -> Void)?
    /// Optional caller-owned live metric (e.g. heart rate), rendered under the
    /// clock as `<prefix>.liveHR`. The HR source stays at the call site; the
    /// overlay adds no acquisition of its own.
    let liveMetric: AnyView?
    @Environment(\.scenePhase) private var scenePhase

    private let total: Int
    @State private var countdown: PhaseCountdownClock
    @State private var now = Date()
    @State private var finished = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(title: String, minutes: Int, tint: Color = .green,
         idPrefix: String, soundsEnabled: Bool = false,
         emphasis: Emphasis = .timer,
         pauseShowsTitle: Bool = true,
         finishTitle: String = String(localized: "Skip"),
         finishSystemImage: String = "stop.fill",
         finishTint: Color = .red,
         onFinish: @escaping (_ elapsedSeconds: Int) -> Void,
         onSkip: ((_ elapsedSeconds: Int) -> Void)? = nil,
         liveMetric: AnyView? = nil) {
        self.liveMetric = liveMetric
        self.title = title
        self.minutes = minutes
        self.tint = tint
        self.idPrefix = idPrefix
        self.soundsEnabled = soundsEnabled
        self.emphasis = emphasis
        self.pauseShowsTitle = pauseShowsTitle
        self.finishTitle = finishTitle
        self.finishSystemImage = finishSystemImage
        self.finishTint = finishTint
        self.onFinish = onFinish
        self.onSkip = onSkip
        let seconds = max(1, minutes) * 60
        self.total = seconds
        _countdown = State(initialValue: PhaseCountdownClock(total: TimeInterval(seconds)))
    }

    private var paused: Bool { countdown.isPaused }

    /// Whole seconds remaining, rounded up so a fresh phase shows its full length
    /// and only drops after a full second elapses.
    private var remaining: Int { Int(countdown.remaining(now: now).rounded(.up)) }

    /// Seconds actually consumed so far, for history reporting.
    private var consumedSeconds: Int { Int(countdown.consumed(now: now).rounded()) }

    private var clock: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    var body: some View {
        ZStack {
            tint.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                Text(title).scaledSystemFont(34, relativeTo: .largeTitle, weight: .heavy, design: .rounded)
                    .accessibilityIdentifier("\(idPrefix).title")
                if emphasis == .liveMetric, let liveMetric {
                    liveMetric
                        .accessibilityIdentifier("\(idPrefix).liveHR")
                    Text(clock)
                        .scaledSystemFont(44, relativeTo: .title, weight: .bold, design: .rounded)
                        .monospacedDigit().contentTransition(.numericText())
                        .accessibilityIdentifier("\(idPrefix).remaining")
                } else {
                    Text(clock)
                        .scaledSystemFont(96, relativeTo: .largeTitle, weight: .black, design: .rounded)
                        .monospacedDigit().contentTransition(.numericText())
                        .accessibilityIdentifier("\(idPrefix).remaining")
                    if let liveMetric {
                        liveMetric
                            .accessibilityIdentifier("\(idPrefix).liveHR")
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Button {
                        let ref = Date()
                        if countdown.isPaused { countdown.resume(now: ref) }
                        else { countdown.pause(now: ref) }
                        now = ref
                    } label: {
                        if pauseShowsTitle {
                            Label(paused ? "Resume" : "Pause",
                                  systemImage: paused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity)
                        } else {
                            Image(systemName: paused ? "play.fill" : "pause.fill")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .cadenceGlassButton(tint: .white)
                    .accessibilityIdentifier("\(idPrefix).pause")
                    .accessibilityLabel(paused ? "Resume" : "Pause")

                    Button {
                        (onSkip ?? onFinish)(consumedSeconds)
                    } label: {
                        Label(finishTitle, systemImage: finishSystemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .cadenceGlassButton(prominent: false, tint: finishTint)
                    .accessibilityIdentifier("\(idPrefix).skip")

                    Button {
                        addTime(60)
                    } label: {
                        Label("1 min", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .cadenceGlassButton(tint: .white)
                    .accessibilityIdentifier("\(idPrefix).addMinute")
                    .accessibilityLabel("Add 1 minute")
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .glassGroup(spacing: 10)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding()
        }
        // Keep the screen awake through the whole warm-up / cool-down timer.
        .keepAwake()
        // Beep sequence as the phase begins (entering warm-up / cool-down).
        .onAppear {
            // Anchor the start to now, so the full duration is honored regardless
            // of any delay between init and appearance.
            countdown = PhaseCountdownClock(total: TimeInterval(total))
            now = Date()
            WorkoutCues.startBeepSequence(enabled: soundsEnabled)
        }
        .onReceive(tick) { date in
            now = date
            guard !finished, !countdown.isPaused else { return }
            if countdown.isFinished(now: date) {
                finished = true
                onFinish(total)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Locking/backgrounding is not a user pause. Refresh from the
            // wall-clock immediately on return; PhaseCountdownClock itself
            // continues across inactive/background spans.
            if phase == .active { now = Date() }
        }
    }

    private func addTime(_ seconds: TimeInterval) {
        let ref = Date()
        countdown.addTime(seconds, now: ref)
        now = ref
    }
}
