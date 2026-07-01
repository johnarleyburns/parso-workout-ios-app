import SwiftUI

/// A guided warm-up / cool-down countdown shown over a workout (feedback batch 4).
/// Generalizes the get-ready countdown: a big `mm:ss` clock, the phase name,
/// Pause/Resume and Skip. When the timer reaches zero — or the user taps Skip —
/// `onFinish` fires (warm-up → opens the session; cool-down → finishes it).
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
    let onFinish: (_ elapsedSeconds: Int) -> Void
    let onSkip: ((_ elapsedSeconds: Int) -> Void)?

    private let total: Int
    @State private var remaining: Int
    @State private var paused = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(title: String, minutes: Int, tint: Color = .green,
         idPrefix: String, soundsEnabled: Bool = false,
         onFinish: @escaping (_ elapsedSeconds: Int) -> Void,
         onSkip: ((_ elapsedSeconds: Int) -> Void)? = nil) {
        self.title = title
        self.minutes = minutes
        self.tint = tint
        self.idPrefix = idPrefix
        self.soundsEnabled = soundsEnabled
        self.onFinish = onFinish
        self.onSkip = onSkip
        let seconds = max(1, minutes) * 60
        self.total = seconds
        _remaining = State(initialValue: seconds)
    }

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
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        paused.toggle()
                    } label: {
                        Label(paused ? "Resume" : "Pause",
                              systemImage: paused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .cadenceGlassButton(tint: .white)
                    .accessibilityIdentifier("\(idPrefix).pause")

                    Button {
                        (onSkip ?? onFinish)(total - remaining)
                    } label: {
                        Label("Skip", systemImage: "forward.fill").frame(maxWidth: .infinity)
                    }
                    .cadenceGlassButton(prominent: true, tint: .black.opacity(0.4))
                    .accessibilityIdentifier("\(idPrefix).skip")
                }
                .glassGroup(spacing: 16)
            }
            .foregroundStyle(.white)
            .padding()
        }
        // Keep the screen awake through the whole warm-up / cool-down timer.
        .keepAwake()
        // Beep sequence as the phase begins (entering warm-up / cool-down).
        .onAppear { WorkoutCues.startBeepSequence(enabled: soundsEnabled) }
        .onReceive(tick) { _ in
            guard !paused, remaining > 0 else { return }
            remaining -= 1
            if remaining <= 0 { onFinish(total) }
        }
    }
}
