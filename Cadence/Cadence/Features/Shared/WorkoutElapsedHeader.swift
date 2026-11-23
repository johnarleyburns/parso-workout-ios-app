import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// A single live row for the strength session: elapsed time / live HR / Work /
/// Rest. `TimelineView` drives every value from the same wall clock, so the
/// Work and Rest stopwatches tick instead of freezing until another redraw.
struct WorkoutElapsedHeader: View {
    let clock: WorkoutClock
    let isPaused: Bool
    @Binding var timers: WorkoutTimersModel
    /// Live metric (heart rate) between the elapsed time and the timers.
    var trailing: AnyView? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let time = Format.duration(clock.elapsed(now: now))
            HStack(spacing: 6) {
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
                separator
                if let trailing {
                    trailing
                    separator
                }
                workRestControl(now: now)
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private var separator: some View {
        Text(verbatim: "/")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// Work / Rest stopwatches on the same row as the workout timer and BPM.
    private func workRestControl(now: Date) -> some View {
        HStack(spacing: 4) {
            timerButton(.work, label: String(localized: "Work"),
                        symbol: "figure.strengthtraining.traditional", now: now)
            timerButton(.rest, label: String(localized: "Rest"),
                        symbol: "pause.circle", now: now)
        }
    }

    private func timerButton(_ mode: WorkoutTimersModel.Mode, label: String,
                             symbol: String, now: Date) -> some View {
        let active = timers.mode == mode
        let value = timers.elapsed(mode, now: now)
        return Button {
            timers.toggle(mode, now: Date())
        } label: {
            VStack(spacing: 0) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                Text(Format.duration(value))
                    .font(.caption2.monospacedDigit())
            }
            .frame(minWidth: 44)
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(active ? (mode == .work ? Color.green : Color.blue).opacity(0.22)
                              : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .foregroundStyle(active ? (mode == .work ? Color.green : Color.blue) : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.timer.\(mode.rawValue)")
        .accessibilityLabel("\(label) timer \(Format.duration(value))\(active ? ", running" : "")")
    }
}
