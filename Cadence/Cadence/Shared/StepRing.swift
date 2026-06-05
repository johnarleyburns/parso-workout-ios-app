import SwiftUI

/// A circular progress ring around the day's step count (FR-3.2). Honors Reduce
/// Motion and exposes an accessible summary.
struct StepRing: View {
    let steps: Int
    let goal: Int

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(steps) / Double(goal))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 16)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [.green, .mint, .green], center: .center),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(Format.integer(steps))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("today.steps")
                Text("of \(Format.integer(goal)) steps")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 200, height: 200)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("today.goalRing")
        .accessibilityLabel("Steps")
        .accessibilityValue("\(steps) of \(goal), \(Int(progress * 100)) percent")
    }
}
