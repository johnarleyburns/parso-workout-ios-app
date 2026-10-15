import SwiftUI
import CadenceCore
import CadenceFeatures

/// This Week page (swipe left from Today): two concentric activity-style rings — outer Strength
/// sets, inner Cardio minutes — with text labels, so colour is never the only signal.
struct WatchWeekView: View {
    let summary: WatchSync.WeekSummary?

    private var rings: [WatchWeekRing] { WatchWeekRings.rings(from: summary) }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height * 0.62)
            VStack(spacing: 4) {
                ZStack {
                    ring(rings[0], diameter: side, lineWidth: max(8, side * 0.11))
                    ring(rings[1], diameter: side * 0.62, lineWidth: max(8, side * 0.11))
                }
                .frame(width: side, height: side)
                .accessibilityHidden(true)
                HStack(spacing: 6) {
                    legend(rings[0], unit: String(localized: "Sets"), title: String(localized: "Strength"))
                    legend(rings[1], unit: String(localized: "Min"), title: String(localized: "Cardio"))
                }
                if summary == nil {
                    Text("Open Cladiron on iPhone to sync.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("This Week")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch.thisWeek")
    }

    private func ring(_ ring: WatchWeekRing, diameter: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Self.color(ring.tone).opacity(0.25), lineWidth: lineWidth)
            Circle().trim(from: 0, to: ring.progress)
                .stroke(Self.color(ring.tone), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private func legend(_ ring: WatchWeekRing, unit: String, title: String) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(Self.color(ring.tone))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("\(ring.displayValue)").font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title): \(ring.displayValue) \(unit) this week"))
        .accessibilityValue(Text(Self.toneText(ring.tone)))
    }

    static func color(_ tone: WatchWeekRingTone) -> Color {
        switch tone {
        case .red: .red
        case .yellow: .yellow
        case .lightBlue: Color(red: 0.45, green: 0.78, blue: 1.0)
        case .green: .green
        }
    }

    static func toneText(_ tone: WatchWeekRingTone) -> String {
        switch tone {
        case .red: String(localized: "None yet")
        case .yellow: String(localized: "Below minimum")
        case .lightBlue: String(localized: "Between minimum and upper limit")
        case .green: String(localized: "At or above upper limit")
        }
    }
}
