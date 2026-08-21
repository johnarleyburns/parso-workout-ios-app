import SwiftUI
import CadenceFeatures

/// The Apple-Watch-style zone palette for live HR (Z1 cyan → Z5 red, neutral =
/// secondary). Lives in the app target because CadenceFeatures cannot depend on
/// SwiftUI; the zone → tint mapping itself is headless in `HRZoneTint`
/// (field-test batch 2026-08-20 issue 7).
extension Color {
    init(hrZoneTint tint: HRZoneTint) {
        switch tint {
        case .zone1: self = .cyan
        case .zone2: self = .green
        case .zone3: self = .yellow
        case .zone4: self = .orange
        case .zone5: self = .red
        case .neutral: self = .secondary
        }
    }
}

/// The shared, glanceable live-HR readout for the cardio live screens
/// (field-test batch 2026-08-20 issue 7): a very large bold, zone-colored BPM
/// with the zone and average beneath — easy to read at a glance, matching the
/// Apple Watch's color scheme. Always mounted; HR off renders a muted "—" and
/// "No heart rate yet" so the layout is stable from the first frame.
///
/// The container is `.accessibilityElement(children: .contain)` (not `.combine`)
/// so the per-metric identifiers (`<prefix>.hr`, `<prefix>.zone`, plus the avg
/// suffix's `<prefix>.avgHr`) stay individually queryable, the repo's standing
/// rule for cards that carry child identifiers.
struct LiveHRBigView: View {
    let bpm: Double?
    let zone: Int
    let avgHR: Double?
    let idPrefix: String
    /// Accessibility fallback label when no BPM has arrived yet.
    var label: String = "Heart Rate"

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "heart.fill")
                    .scaledSystemFont(48, relativeTo: .largeTitle, weight: .heavy)
                Text(LiveHRPresenter.bpmText(bpm))
                    .scaledSystemFont(84, relativeTo: .largeTitle, weight: .heavy, design: .rounded)
                    .monospacedDigit()
                    .accessibilityIdentifier("\(idPrefix).hr")
            }
            .foregroundStyle(tint)

            if bpm == nil {
                Text("No heart rate yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(idPrefix).zone")
            } else {
                HStack(spacing: 0) {
                    Text(LiveHRPresenter.zoneLine(zone: zone))
                        .foregroundStyle(tint)
                        .accessibilityIdentifier("\(idPrefix).zone")
                    Text(LiveHRPresenter.avgSuffix(avgHR: avgHR))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("\(idPrefix).avgHr")
                }
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .frame(maxWidth: .infinity)
    }

    private var tint: Color {
        bpm == nil ? .secondary : Color(hrZoneTint: HRZoneTint.tint(for: zone))
    }

    private var accessibilityText: String {
        guard let bpm else { return "\(label), no reading yet" }
        var text = "\(Int(bpm.rounded())) beats per minute, zone \(zone)"
        if let avgHR { text += ", average \(Int(avgHR.rounded()))" }
        return text
    }
}
