import SwiftUI

/// A small current-time label for workout screens (issue 10) — the wall clock the
/// user can glance at without leaving the workout. Ticks once a minute. Reused
/// across the strength, outdoor, timer-cardio, interval, and swim headers.
struct WallClockLabel: View {
    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

    var body: some View {
        let text = Self.formatter.string(from: now)
        return HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workout.wallClock")
        .accessibilityLabel("Current time \(text)")
        .onReceive(tick) { now = $0 }
    }
}
