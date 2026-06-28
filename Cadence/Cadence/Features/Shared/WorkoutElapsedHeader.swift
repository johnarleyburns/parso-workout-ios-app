import SwiftUI
import CadenceCore

/// A prominent, always-visible elapsed-time header for the strength
/// session screen (field-testing Round 4 P2, feedback #7). Cardio and interval
/// screens already show a large clock; strength sessions had none, so the
/// in-workout time wasn't visible while logging sets.
///
/// The value is read from the session's `WorkoutClock`, which derives elapsed
/// from wall-clock dates and excludes paused spans — so this display freezes the
/// instant a workout is paused and stays correct across backgrounding. The 1 Hz
/// timer here is only a redraw tick; the clock is the source of truth.
struct WorkoutElapsedHeader: View {
    let clock: WorkoutClock
    let isPaused: Bool

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let time = Format.duration(clock.elapsed(now: now))
        return HStack(spacing: 12) {
            Image(systemName: "stopwatch")
                .font(.title2)
                .foregroundStyle(isPaused ? .secondary : .primary)
            Text(time)
                .scaledSystemFont(44, relativeTo: .largeTitle, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(isPaused ? .secondary : .primary)
                .accessibilityIdentifier("session.elapsed")
                .accessibilityLabel("Elapsed time \(time)\(isPaused ? ", paused" : "")")
            if isPaused {
                Text("Paused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.orange.opacity(0.18), in: Capsule())
                    .accessibilityIdentifier("session.elapsed.paused")
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .onReceive(tick) { now = $0 }
    }
}
