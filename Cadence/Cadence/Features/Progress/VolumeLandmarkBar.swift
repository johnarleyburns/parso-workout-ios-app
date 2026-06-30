import SwiftUI
import CadenceCore

/// One muscle's weekly working-set count placed against experience-scaled volume bands.
/// Zone color encodes `VolumeZone`; the marker is the user's set count.
struct VolumeLandmarkBar: View {
    let part: BodyPart
    let sets: Double
    let bands: VolumeBands
    let zone: VolumeZone

    private var scaleMax: Double { max(bands.mrv * 1.25, sets * 1.05, 1) }
    private func frac(_ v: Double) -> CGFloat { CGFloat(min(max(v / scaleMax, 0), 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(part.displayName).font(.caption)
                Spacer()
                Text("\(setsText) sets \u{00b7} \(zone.label)")
                    .font(.caption).foregroundStyle(zone.tint)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.orange.opacity(0.18)).frame(width: w * frac(bands.mev))
                        Rectangle().fill(Color.green.opacity(0.18)).frame(width: w * (frac(bands.mav) - frac(bands.mev)))
                        Rectangle().fill(Color.orange.opacity(0.18)).frame(width: w * (frac(bands.mrv) - frac(bands.mav)))
                        Rectangle().fill(Color.red.opacity(0.18))
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(zone.tint)
                        .frame(width: 3, height: 12)
                        .offset(x: min(w * frac(sets), w - 3))
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress.volume.\(part.rawValue)")
        .accessibilityLabel("\(part.displayName): \(setsText) sets, \(zone.label)")
    }

    private var setsText: String {
        sets == sets.rounded() ? String(Int(sets)) : String(format: "%.1f", sets)
    }
}

extension VolumeZone {
    var label: String {
        switch self {
        case .belowMEV:       "below starting range"
        case .productive:     "in starting range"
        case .approachingMRV: "near high end"
        case .overMRV:        "above high range"
        }
    }
    var tint: Color {
        switch self {
        case .belowMEV:       .orange
        case .productive:     .green
        case .approachingMRV: .orange
        case .overMRV:        .red
        }
    }
}
