import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// A single live row for the strength session: elapsed workout time, live HR,
/// and one always-on Work-or-Rest interval. `TimelineView` drives every value
/// from the same wall clock, so the interval ticks without another redraw.
struct WorkoutElapsedHeader: View {
    let clock: WorkoutClock
    let isPaused: Bool
    @Binding var timers: WorkoutTimersModel
    /// Live metric (heart rate) between the elapsed time and the interval.
    var trailing: AnyView? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let time = Format.duration(clock.elapsed(now: now))
            HStack(spacing: 10) {
                Image(systemName: "stopwatch")
                    .font(.subheadline)
                    .foregroundStyle(isPaused ? .secondary : .primary)
                Text(time)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .allowsTightening(true)
                    .foregroundStyle(isPaused ? .secondary : .primary)
                    .accessibilityIdentifier("session.elapsed")
                    .accessibilityLabel("Elapsed time \(time)\(isPaused ? ", paused" : "")")
                if isPaused {
                    Text("Paused")
                        .font(.caption2.weight(.semibold))
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("session.elapsed.paused")
                }
                if let trailing {
                    trailing
                }
                intervalTimer(now: now)
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    /// The single Work/Rest stopwatch. It is display-only: opening the editor
    /// starts work, and logging or leaving the editor starts rest.
    private func intervalTimer(now: Date) -> some View {
        let value = Format.duration(timers.elapsed(now: now))
        let label = timers.mode == .work ? String(localized: "Work") : String(localized: "Rest")
        let tint: Color = timers.mode == .work ? .green : .blue
        return HStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
            Text(value)
                .font(.caption2.monospacedDigit())
        }
        .frame(minWidth: 58)
        .padding(.vertical, 4)
        .padding(.horizontal, 5)
        .background(tint.opacity(timers.isRunning ? 0.22 : 0.10),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .foregroundStyle(timers.isRunning ? tint : Color.secondary)
        .accessibilityIdentifier("session.timer.interval")
        .accessibilityLabel("\(label) interval \(value)\(timers.isRunning ? ", running" : ", paused")")
    }
}
