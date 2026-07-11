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
///
/// Also hosts the wall clock (top-left, issue 10) and a Work/Rest stopwatch
/// (right, issue 9) whose state lives in the caller-owned `WorkoutTimersModel`.
struct WorkoutElapsedHeader: View {
    let clock: WorkoutClock
    let isPaused: Bool
    @Binding var timers: WorkoutTimersModel

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let time = Format.duration(clock.elapsed(now: now))
        return VStack(spacing: 6) {
            HStack {
                WallClockLabel()
                Spacer()
            }
            HStack(spacing: 12) {
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
                workRestControl
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .onReceive(tick) { now = $0 }
    }

    /// A two-button Work / Rest stopwatch. Tapping a mode starts it (and banks the
    /// other); tapping the active mode stops it. Each shows its running total.
    private var workRestControl: some View {
        HStack(spacing: 6) {
            timerButton(.work, label: "Work", symbol: "figure.strengthtraining.traditional")
            timerButton(.rest, label: "Rest", symbol: "pause.circle")
        }
    }

    private func timerButton(_ mode: WorkoutTimersModel.Mode, label: String, symbol: String) -> some View {
        let active = timers.mode == mode
        let value = timers.elapsed(mode, now: now)
        return Button {
            timers.toggle(mode, now: Date())
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                Text(Format.duration(value))
                    .font(.caption2.monospacedDigit())
            }
            .frame(minWidth: 46)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(active ? (mode == .work ? Color.green : Color.blue).opacity(0.22) : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(active ? (mode == .work ? Color.green : Color.blue) : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.timer.\(mode.rawValue)")
        .accessibilityLabel("\(label) timer \(Format.duration(value))\(active ? ", running" : "")")
    }
}
