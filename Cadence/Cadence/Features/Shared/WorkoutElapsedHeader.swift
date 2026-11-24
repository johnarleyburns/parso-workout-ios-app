import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// A single live row for the strength session: elapsed workout time, live HR,
/// and one always-on Work-or-Rest interval. `TimelineView` drives every value
/// from the same wall clock, so the interval ticks without another redraw.
///
/// Tapping the Work/Rest pill swaps intervals: tapping Work pauses Work and
/// starts Rest, tapping Rest pauses Rest and starts Work. The pill is the only
/// control, so a quick tap is enough to switch.
struct WorkoutElapsedHeader: View {
    let clock: WorkoutClock
    let isPaused: Bool
    @Binding var timers: WorkoutTimersModel
    /// Live metric (heart rate) centered between the elapsed time and interval.
    var trailing: AnyView? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let time = Format.duration(clock.elapsed(now: now))
            ZStack {
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

                    Spacer(minLength: 0)

                    intervalTimerButton(now: now)
                }

                if let trailing {
                    trailing
                        .accessibilityIdentifier("session.hr.center")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    /// One Work/Rest stopwatch. Opening the editor starts work; logging or
    /// leaving the editor starts rest; tapping the pill switches between them.
    private func intervalTimerButton(now: Date) -> some View {
        let value = Format.duration(timers.elapsed(now: now))
        let label = timers.mode == .work ? String(localized: "Work") : String(localized: "Rest")
        let nextLabel = timers.mode == .work ? String(localized: "Rest") : String(localized: "Work")
        let tint: Color = timers.mode == .work ? .green : .blue
        return Button {
            let ref = Date()
            if timers.mode == .work {
                timers.beginRest(now: ref)
            } else {
                timers.beginWork(now: ref)
            }
            Haptics.selection()
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.subheadline.weight(.bold))
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            .frame(minWidth: 92, alignment: .trailing)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(tint.opacity(timers.isRunning ? 0.22 : 0.10),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .foregroundStyle(timers.isRunning ? tint : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.timer.interval")
        .accessibilityLabel("\(label) interval \(value)\(timers.isRunning ? ", running" : ", paused")")
        .accessibilityHint("Switches to the \(nextLabel) interval")
    }
}
