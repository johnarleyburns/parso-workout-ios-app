import SwiftUI
import CadenceFeatures

/// Two glanceable weekly rings (strength sets, cardio minutes); each taps through to its tab.
struct WeeklyIntentRingsCard: View {
    let display: WeeklyIntentDisplay
    @Binding var tabSelection: RootTabView.Tab
    @ScaledMetric(relativeTo: .title) private var ringDiameter: CGFloat = 64

    var body: some View {
        HStack(spacing: 16) {
            ring(display.strengthRing, identifierPrefix: "strengthRing") { tabSelection = .strength }
            ring(display.cardioRing, identifierPrefix: "cardioRing") { tabSelection = .cardio }
        }
    }

    private func ring(_ r: WeeklyIntentRingDisplay, identifierPrefix: String,
                      onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ProgressView(value: r.normalizedProgress)
                    .progressViewStyle(.circular)
                    .controlSize(.extraLarge)
                    .tint(CadenceTheme.weeklyTint(r.tintRole))
                    .frame(width: ringDiameter, height: ringDiameter)
                Text(r.valueText)
                    .font(.headline.monospacedDigit())
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.accessibilityLabel)
        .accessibilityValue(r.accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.weeklyIntent.\(identifierPrefix)")
    }
}
