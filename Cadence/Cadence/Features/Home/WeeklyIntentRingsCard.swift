import SwiftUI
import CadenceFeatures

/// A compact, determinate weekly activity display. Strength is the outer ring;
/// cardio is the inner ring, matching the Watch's This Week presentation.
struct WeeklyIntentRingsCard: View {
    let display: WeeklyIntentDisplay
    @Binding var tabSelection: RootTabView.Tab
    @ScaledMetric(relativeTo: .title) private var ringDiameter: CGFloat = 104

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ring(display.strengthRing, diameter: ringDiameter, lineWidth: max(8, ringDiameter * 0.11))
                ring(display.cardioRing, diameter: ringDiameter * 0.62, lineWidth: max(8, ringDiameter * 0.11))
            }
            .frame(width: ringDiameter, height: ringDiameter)
            .accessibilityHidden(true)
            HStack(spacing: 16) {
                legend(display.strengthRing, title: String(localized: "Strength"),
                       identifierPrefix: "strengthRing") { tabSelection = .strength }
                legend(display.cardioRing, title: String(localized: "Cardio"),
                       identifierPrefix: "cardioRing") { tabSelection = .cardio }
            }
        }
    }

    private func ring(_ ring: WeeklyIntentRingDisplay, diameter: CGFloat, lineWidth: CGFloat) -> some View {
        let color = CadenceTheme.weeklyTint(ring.tintRole)
        return ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle().trim(from: 0, to: ring.normalizedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private func legend(_ ring: WeeklyIntentRingDisplay, title: String, identifierPrefix: String,
                        onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CadenceTheme.weeklyTint(ring.tintRole))
                Text(ring.valueText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ring.accessibilityLabel)
        .accessibilityValue(ring.accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.weeklyIntent.\(identifierPrefix)")
    }
}
