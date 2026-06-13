import SwiftUI

/// A guided warm-up / cool-down countdown shown over a workout (feedback batch 4).
/// Generalizes the get-ready countdown: a big `mm:ss` clock, the phase name,
/// Pause/Resume and Skip. When the timer reaches zero — or the user taps Skip —
/// `onFinish` fires (warm-up → opens the session; cool-down → finishes it).
///
/// `idPrefix` namespaces the accessibility ids ("warmup"/"cooldown") so the two
/// surfaces are individually addressable in UI tests:
/// `<prefix>.remaining`, `<prefix>.pause`, `<prefix>.skip`.
struct GuidedPhaseOverlay: View {
    let title: String
    let minutes: Int
    var tint: Color = .green
    var idPrefix: String
    let onFinish: () -> Void

    @State private var remaining: Int
    @State private var paused = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(title: String, minutes: Int, tint: Color = .green,
         idPrefix: String, onFinish: @escaping () -> Void) {
        self.title = title
        self.minutes = minutes
        self.tint = tint
        self.idPrefix = idPrefix
        self.onFinish = onFinish
        _remaining = State(initialValue: max(1, minutes) * 60)
    }

    private var clock: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    var body: some View {
        ZStack {
            tint.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Text(title).font(.system(size: 34, weight: .heavy, design: .rounded))
                    .accessibilityIdentifier("\(idPrefix).title")
                Text(clock)
                    .font(.system(size: 96, weight: .black, design: .rounded))
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
                    .buttonStyle(.bordered).controlSize(.large).tint(.white)
                    .accessibilityIdentifier("\(idPrefix).pause")

                    Button {
                        onFinish()
                    } label: {
                        Label("Skip", systemImage: "forward.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(.black.opacity(0.4))
                    .accessibilityIdentifier("\(idPrefix).skip")
                }
            }
            .foregroundStyle(.white)
            .padding()
        }
        .onReceive(tick) { _ in
            guard !paused, remaining > 0 else { return }
            remaining -= 1
            if remaining <= 0 { onFinish() }
        }
    }
}
