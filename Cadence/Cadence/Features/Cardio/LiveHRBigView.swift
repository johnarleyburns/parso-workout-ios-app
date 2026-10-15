import SwiftUI
import Charts
import CadenceCore
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

/// Semi-transparent HR-zone background bands for HR charts, plus a bold white
/// HR line. Bands follow the user's actual max HR (override, else age estimate).
struct HRZoneChart: View {
    let samples: [(t: Double, bpm: Double)]
    let maxHR: Double
    var body: some View {
        let domain = HRZoneBands.domain(bpms: samples.map(\.bpm), maxHR: maxHR)
        Chart {
            ForEach(HRZoneBands.bands(maxHR: maxHR, domain: domain), id: \.zone) { band in
                RectangleMark(yStart: .value("Zone start", band.lower),
                              yEnd: .value("Zone end", band.upper))
                    .foregroundStyle(Color(hrZoneTint: band.tint).opacity(0.3))
            }
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                LineMark(x: .value("Time", sample.t / 60), y: .value("BPM", sample.bpm))
                    .foregroundStyle(.white)
                    .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            }
        }
        .chartYScale(domain: domain)
        .chartXAxisLabel("min")
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
    var intensityProfile: CardioIntensityProfile? = nil
    /// Accessibility fallback label when no BPM has arrived yet.
    var label: String = String(localized: "Heart Rate")

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
                if let bpm, let profile = intensityProfile {
                    let classification = CardioIntensityClassifier.classify(heartRate: bpm, profile: profile)
                    Text(" · \(classification.relativeIntensity.displayName)")
                        .foregroundStyle(tint)
                        .accessibilityIdentifier("\(idPrefix).intensity")
                }
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
        var text = String(localized: "\(Int(bpm.rounded())) beats per minute, zone \(zone)")
        if let profile = intensityProfile {
            text += ", \(CardioIntensityClassifier.classify(heartRate: bpm, profile: profile).relativeIntensity.displayName.lowercased())"
        }
        if let avgHR { text += ", average \(Int(avgHR.rounded()))" }
        return text
    }
}
