import SwiftUI
import Combine
import CadenceCore

/// A guided warm-up / cool-down countdown shown over a workout (feedback batch 4).
/// Generalizes the get-ready countdown: a big `mm:ss` clock, the phase name,
/// +1/+5 minute extenders, Pause/Resume, and the phase's finish action (Skip for
/// warm-up, End for cool-down). When the timer reaches zero — or the user taps
/// that finish action — `onFinish` fires (warm-up → opens the session; cool-down
/// → finishes it).
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
    let title: String
    let minutes: Int
    var tint: Color = .green
    var idPrefix: String
    /// Play a transition bell when this phase begins (batch 7 item 9).
    var soundsEnabled: Bool = false
    /// The phase's second action matches the workout dock: warm-up skips ahead,
    /// cool-down ends the workout.
    var finishTitle: String = String(localized: "Skip")
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
         finishTitle: String = String(localized: "Skip"),
         onFinish: @escaping (_ elapsedSeconds: Int) -> Void,
         onSkip: ((_ elapsedSeconds: Int) -> Void)? = nil,
         liveMetric: AnyView? = nil) {
        self.liveMetric = liveMetric
        self.title = title
        self.minutes = minutes
        self.tint = tint
        self.idPrefix = idPrefix
        self.soundsEnabled = soundsEnabled
        self.finishTitle = finishTitle
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
            VStack(spacing: 24) {
                Spacer()
                Text(title).scaledSystemFont(34, relativeTo: .largeTitle, weight: .heavy, design: .rounded)
                    .accessibilityIdentifier("\(idPrefix).title")
                Text(clock)
                    .scaledSystemFont(96, relativeTo: .largeTitle, weight: .black, design: .rounded)
                    .monospacedDigit().contentTransition(.numericText())
                    .accessibilityIdentifier("\(idPrefix).remaining")
                if let liveMetric {
                    liveMetric
                        .accessibilityIdentifier("\(idPrefix).liveHR")
                }
                Spacer()
                VStack(spacing: 10) {
                    Button {
                        addTime(60)
                    } label: {
                        Label("+1 min", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .cadenceGlassButton(tint: .white)
                    .accessibilityIdentifier("\(idPrefix).addMinute")

                    Button {
                        addTime(300)
                    } label: {
                        Label("+5 min", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .cadenceGlassButton(tint: .white)
                    .accessibilityIdentifier("\(idPrefix).addFiveMinutes")

                    HStack(spacing: 10) {
                        Button {
                            let ref = Date()
                            if countdown.isPaused { countdown.resume(now: ref) }
                            else { countdown.pause(now: ref) }
                            now = ref
                        } label: {
                            Label(paused ? "Resume" : "Pause",
                                  systemImage: paused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .cadenceGlassButton(tint: .white)
                        .accessibilityIdentifier("\(idPrefix).pause")

                        Button {
                            (onSkip ?? onFinish)(consumedSeconds)
                        } label: {
                            Label(finishTitle, systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .cadenceGlassButton(prominent: true, tint: .black.opacity(0.4))
                        .accessibilityIdentifier("\(idPrefix).skip")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .glassGroup(spacing: 10)
            }
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
