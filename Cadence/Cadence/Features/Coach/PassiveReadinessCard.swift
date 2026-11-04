import SwiftUI
import CadenceCore
import CadenceFeatures

/// Home Coach-card line surfacing the passive-readiness signal (HRV/sleep/RHR) with
/// tappable citations. The copy + citation IDs come from `PassiveReadinessPresenter`
/// (headless, tested); this view only renders them via `CoachSourcesLink`.
struct PassiveReadinessCard: View {
    let display: PassiveReadinessPresenter.Display

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.tint)
                Text(display.message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if display.promptCheckIn {
                Text("20 seconds to tell the coach how you feel? Your check-in always wins over these signals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CoachSourcesLink(citationIds: display.citationIds, identifier: "coach.passiveReadiness.science")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.passiveReadiness")
    }
}
