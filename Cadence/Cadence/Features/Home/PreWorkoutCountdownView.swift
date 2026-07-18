import SwiftUI

/// A "get ready" countdown shown before a workout begins (default 30s, settable
/// down or to 0 to disable). Big, legible, with Skip and Cancel.
struct PreWorkoutCountdownView: View {
    let seconds: Int
    let onStart: () -> Void
    let onCancel: () -> Void

    @State private var remaining: Int
    @State private var scale = 1.0
    @State private var paused = false
    @State private var showSkipConfirmation = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(seconds: Int, onStart: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.seconds = seconds
        self.onStart = onStart
        self.onCancel = onCancel
        _remaining = State(initialValue: max(0, seconds))
    }

    var body: some View {
        ZStack {
            Color.green.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Text("Get Ready").scaledSystemFont(34, relativeTo: .largeTitle, weight: .heavy, design: .rounded)
                Text("\(remaining)")
                    .scaledSystemFont(140, relativeTo: .largeTitle, weight: .black, design: .rounded)
                    .monospacedDigit().contentTransition(.numericText())
                    .scaleEffect(scale)
                    .accessibilityIdentifier("countdown.remaining")
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
                    .accessibilityIdentifier("countdown.pause")

                    Button {
                        showSkipConfirmation = true
                    } label: { Label("Skip", systemImage: "forward.fill").frame(maxWidth: .infinity) }
                        .cadenceGlassButton(prominent: true, tint: .black.opacity(0.4))
                        .accessibilityIdentifier("countdown.skip")
                }
                .glassGroup(spacing: 16)
                Button("Cancel") { onCancel() }
                    .accessibilityIdentifier("countdown.cancel")
                    .padding(.bottom)
            }
            .foregroundStyle(.white)
            .padding()
        }
        .confirmationDialog("Skip countdown?", isPresented: $showSkipConfirmation, titleVisibility: .visible) {
            Button("Skip", role: .destructive) { onStart() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Start workout immediately.")
        }
        // Part of the workout start sequence — no auto-lock (Phase 1c).
        .keepAwake()
        .onAppear { if remaining <= 0 { onStart() } }
        .onReceive(tick) { _ in
            guard !paused, remaining > 0 else { return }
            withAnimation(.easeOut(duration: 0.2)) { scale = 1.25 }
            withAnimation(.easeIn(duration: 0.6).delay(0.2)) { scale = 1.0 }
            remaining -= 1
            if remaining <= 0 { onStart() }
        }
    }
}
