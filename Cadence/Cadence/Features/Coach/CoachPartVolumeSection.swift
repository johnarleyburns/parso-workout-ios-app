import SwiftUI
import CadenceCore
import CadenceFeatures

/// Body-part volume vs plan section (§1). Rendered as a standalone
/// SwiftUI view to keep `YourWeekView` under the ratchet ceiling.
struct CoachPartVolumeSection: View {
    let trainingFacts: TrainingFacts
    let optimizedPlan: OptimizedCoachPlan

    var body: some View {
        Section {
            VStack(spacing: 8) {
                summaryHeader
                Divider()
                ForEach(volumeRows) { row in
                    partVolumeRow(row)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Body-part volume vs plan")
        } footer: {
            if let citation = CitationRegistry.citation(forId: "volumeDoseResponse") {
                CitationLink(citation: citation, compact: true)
            }
        }
        .accessibilityIdentifier("yourPlan.partVolume")
    }

    // MARK: - Computed

    private var volumeRows: [WeekVolumePresenter.PartRow] {
        WeekVolumePresenter.rows(facts: trainingFacts, optimized: optimizedPlan)
    }

    private var volumeSummary: WeekVolumePresenter.Summary {
        WeekVolumePresenter.summary(rows: volumeRows)
    }

    // MARK: - Aggregate header

    private var summaryHeader: some View {
        Group {
            HStack {
                Text("Sets this week").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Format.sets(volumeSummary.doneSets)) done + \(Format.sets(volumeSummary.plannedSets)) planned")
                    .font(.subheadline.bold()).monospacedDigit()
            }
            HStack(spacing: 0) {
                Text("of ~\(Int(volumeSummary.recommendedSets.rounded())) recommended")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            let maxScale = max(1, volumeRows.map { max($0.barFractionDone + $0.barFractionPlanned, $0.mevTickFraction) }.max() ?? 1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray5)).frame(height: 8)
                    let totalDoneFrac = min(1, maxScale > 0 ? volumeSummary.doneSets / (volumeSummary.recommendedSets * 1.2) : 0)
                    RoundedRectangle(cornerRadius: 3).fill(Color.green)
                        .frame(width: max(0, geo.size.width * totalDoneFrac), height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Per-part row

    private func partVolumeRow(_ row: WeekVolumePresenter.PartRow) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(row.part.displayName).font(.subheadline)
                    .accessibilityHidden(true)
                Spacer()
                Group {
                    if row.plannedSets > 0 {
                        Text("\(Format.sets(row.doneSets)) done + \(Format.sets(row.plannedSets)) planned")
                    } else {
                        Text("\(Format.sets(row.doneSets)) done")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityHidden(true)

                statusChip(row.status)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("yourPlan.partVolume.\(row.part.rawValue)")
            .accessibilityLabel(accessibilityLabel(for: row))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)

                    if row.barFractionDone > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(for: row.status))
                            .frame(width: max(0, geo.size.width * min(1, row.barFractionDone)), height: 6)
                    }

                    if row.barFractionPlanned > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(for: row.status).opacity(0.5))
                            .frame(width: max(0, geo.size.width * min(1, row.barFractionPlanned)), height: 6)
                            .offset(x: max(0, geo.size.width * row.barFractionDone))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: max(0, geo.size.width * min(1, row.barFractionPlanned)), height: 6)
                                    .offset(x: max(0, geo.size.width * row.barFractionDone))
                                    .mask(hatchPattern)
                            }
                    }

                    if row.mevTickFraction > 0 {
                        Rectangle()
                            .fill(Color(.systemGray3))
                            .frame(width: 2, height: 10)
                            .offset(x: max(0, geo.size.width * row.mevTickFraction - 1))
                    }
                }
            }
            .frame(height: 10)
        }
    }

    // MARK: - Helpers

    private func statusChip(_ status: WeekVolumePresenter.PartRow.Status) -> some View {
        Group {
            switch status {
            case .targetMet:
                Text("✓ target met")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            case .onTrack:
                Text("✓ target range")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.teal)
            case .short(let toGo):
                Text("⚠ \(Int(toGo.rounded())) to go")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            case .high:
                Text("↑ high")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(chipBackground(for: status), in: RoundedRectangle(cornerRadius: 5))
    }

    private func barColor(for status: WeekVolumePresenter.PartRow.Status) -> Color {
        switch status {
        case .targetMet, .onTrack: return .green
        case .short: return .orange
        case .high: return .gray
        }
    }

    private func chipBackground(for status: WeekVolumePresenter.PartRow.Status) -> Color {
        switch status {
        case .targetMet: return .green.opacity(0.14)
        case .onTrack: return .teal.opacity(0.14)
        case .short: return .orange.opacity(0.16)
        case .high: return Color(.systemGray5)
        }
    }

    private var hatchPattern: some View {
        Canvas { context, size in
            let stride: CGFloat = 4
            var x: CGFloat = 0
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x - size.height, y: size.height))
                path.addLine(to: CGPoint(x: x - size.height + 2, y: size.height))
                path.addLine(to: CGPoint(x: x + 2, y: 0))
                path.closeSubpath()
                context.fill(path, with: .color(.white.opacity(0.35)))
                x += stride
            }
        }
    }

    private func accessibilityLabel(for row: WeekVolumePresenter.PartRow) -> String {
        let statusText: String
        switch row.status {
        case .targetMet: statusText = "target met"
        case .onTrack: statusText = "within target range"
        case .short(let toGo): statusText = "\(Int(toGo.rounded())) sets to go"
        case .high: statusText = "above maximum recommended"
        }
        return "\(row.part.displayName): \(Format.sets(row.doneSets)) sets done, \(Format.sets(row.plannedSets)) planned, \(statusText). Recommended \(Int(row.band.lowerBound.rounded())) to \(Int(row.band.upperBound.rounded()))."
    }
}
