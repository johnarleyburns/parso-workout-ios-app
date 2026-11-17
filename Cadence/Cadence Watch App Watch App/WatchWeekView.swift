import SwiftUI
import CadenceCore
import CadenceFeatures

/// This Week page (swipe left from Today): two concentric activity-style rings — outer Strength
/// sets, inner Cardio minutes — with text labels, so colour is never the only signal.
struct WatchWeekView: View {
    let summary: WatchSync.WeekSummary?
    var overlays: [WatchWeekLocalOverlay] = []
    var currentWeekKey: String

    private var rings: [WatchWeekRing] {
        WatchWeekRings.rings(baseline: summary, overlays: overlays, currentWeekKey: currentWeekKey)
    }

    var body: some View {
        ScrollView {
            // Width stays constant when page chrome changes during a swipe.
            // Height-dependent sizing made the rings jump after the toolbar settled.
            VStack(spacing: 14) {
                GeometryReader { proxy in
                    let side = proxy.size.width / 1.14
                    ZStack {
                        ring(rings[0], diameter: side, lineWidth: side * 0.11)
                        ring(rings[1], diameter: side * 0.62, lineWidth: side * 0.11)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 156)
                .accessibilityHidden(true)
                HStack(spacing: 6) {
                    legend(rings[0], unit: String(localized: "Sets"), title: String(localized: "Strength"))
                    legend(rings[1], unit: String(localized: "Min"), title: String(localized: "Cardio"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch.thisWeek")
    }

    private func ring(_ ring: WatchWeekRing, diameter: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Self.color(ring.tone, cardio: ring.kind == .cardio).opacity(0.25), lineWidth: lineWidth)
            Circle().trim(from: 0, to: ring.progress)
                .stroke(Self.color(ring.tone, cardio: ring.kind == .cardio), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private func legend(_ ring: WatchWeekRing, unit: String, title: String) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(Self.color(ring.tone, cardio: ring.kind == .cardio))
            Text("\(ring.displayValue)").font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Self.color(ring.tone, cardio: ring.kind == .cardio))
            Text(unit).font(.caption2).foregroundStyle(Self.color(ring.tone, cardio: ring.kind == .cardio))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title): \(ring.displayValue) \(unit) this week"))
        .accessibilityValue(Text(Self.toneText(ring.tone)))
    }

    static func color(_ tone: WatchWeekRingTone, cardio: Bool = false) -> Color {
        let role: WeeklySetTintRole = switch tone {
        case .red: .red
        case .yellow: .yellow
        case .lightGreen: .lightGreen
        case .green: .green
        }
        let rgb = WeeklyActivityPalette.color(role, cardio: cardio)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func toneText(_ tone: WatchWeekRingTone) -> String {
        switch tone {
        case .red: String(localized: "None yet")
        case .yellow: String(localized: "Below minimum")
        case .lightGreen: String(localized: "Between minimum and upper limit")
        case .green: String(localized: "At or above upper limit")
        }
    }
}
