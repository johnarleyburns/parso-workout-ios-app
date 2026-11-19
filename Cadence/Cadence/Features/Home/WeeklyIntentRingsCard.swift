import SwiftUI
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// A compact, determinate weekly activity display. Strength is the outer ring;
/// cardio is the inner ring, matching the Watch's This Week presentation.
struct WeeklyIntentRingsCard: View {
    let display: WeeklyIntentDisplay
    @Binding var tabSelection: RootTabView.Tab
    @ScaledMetric(relativeTo: .title) private var ringDiameter: CGFloat = 148

    var body: some View {
        // The card owns the Today page's free vertical space: the gauge is
        // centred in the area above the legends, and the Strength/Cardio
        // labels stay pinned to the card's bottom edge.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                ring(display.strengthRing, cardio: false, diameter: ringDiameter, lineWidth: max(8, ringDiameter * 0.11))
                ring(display.cardioRing, cardio: true, diameter: ringDiameter * 0.62, lineWidth: max(8, ringDiameter * 0.11))
            }
            .frame(width: ringDiameter, height: ringDiameter)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                legend(display.strengthRing, title: String(localized: "Strength"),
                       identifierPrefix: "strengthRing", cardio: false) { tabSelection = .strength }
                legend(display.cardioRing, title: String(localized: "Cardio"),
                       identifierPrefix: "cardioRing", cardio: true) { tabSelection = .cardio }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ring(_ ring: WeeklyIntentRingDisplay, cardio: Bool, diameter: CGFloat, lineWidth: CGFloat) -> some View {
        let color = activityColor(ring.tintRole, cardio: cardio)
        return ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle().trim(from: 0, to: ring.normalizedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private func activityColor(_ role: WeeklySetTintRole, cardio: Bool) -> Color {
        let rgb = WeeklyActivityPalette.color(role, cardio: cardio)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func legend(_ ring: WeeklyIntentRingDisplay, title: String, identifierPrefix: String, cardio: Bool,
                        onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(activityColor(ring.tintRole, cardio: cardio))
                Text(ring.valueText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(activityColor(ring.tintRole, cardio: cardio))
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
