import SwiftUI
import Observation

/// Rest-timer state (FR-1.5). Decrement logic is in `tick()` (not wall-clock) so
/// it is deterministic and unit-testable; the view drives `tick()` on a 1s timer.
@Observable
final class RestTimerModel {
    private(set) var remaining: Int = 0
    private(set) var total: Int = 0
    private(set) var isRunning = false

    func start(seconds: Int) {
        total = seconds
        remaining = seconds
        isRunning = seconds > 0
    }

    func tick() {
        guard isRunning else { return }
        remaining = max(0, remaining - 1)
        if remaining == 0 { isRunning = false }
    }

    func add(_ seconds: Int) {
        guard isRunning || remaining > 0 else { return }
        remaining += seconds
        total = max(total, remaining)
        if remaining > 0 { isRunning = true }
    }

    func skip() {
        remaining = 0
        isRunning = false
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(total - remaining) / Double(total)
    }
}

/// The "Rest · 0:47" pill at the top of the session screen.
struct RestTimerBar: View {
    @Bindable var model: RestTimerModel
    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSkipConfirmation = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
            Text("Rest")
                .fontWeight(.semibold)
            Text(Format.clock(model.remaining))
                .monospacedDigit()
                .accessibilityIdentifier("rest.remaining")
            Spacer(minLength: 8)
            Button("+30s") { model.add(30) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .lineLimit(1).fixedSize()
                .accessibilityIdentifier("rest.add30")
            Button("Skip") { showSkipConfirmation = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .lineLimit(1).fixedSize()
                .frame(minWidth: 56)
                .accessibilityIdentifier("rest.skip")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cadenceGlass(in: Capsule(), fallback: .thinMaterial)
        .overlay(alignment: .bottom) {
            ProgressView(value: model.progress)
                .padding(.horizontal, 32)
                .opacity(reduceMotion ? 0 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rest.bar")
        .accessibilityLabel("Rest timer, \(model.remaining) seconds remaining")
        .confirmationDialog("Skip rest?", isPresented: $showSkipConfirmation, titleVisibility: .visible) {
            Button("Skip", role: .destructive) { model.skip() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rest will end immediately.")
        }
        .onReceive(timer) { _ in
            let wasRunning = model.isRunning
            model.tick()
            if wasRunning && !model.isRunning { onComplete() }
        }
    }
}
