import SwiftUI
import CadenceCore
import CadenceFeatures

/// Muscle-group volume vs plan section (§1). Rendered as a standalone
/// SwiftUI view to keep `YourWeekView` under the ratchet ceiling.
struct CoachPartVolumeSection: View {
    let trainingFacts: TrainingFacts
    let optimizedPlan: OptimizedCoachPlan
    @State private var volumeWarningMessage: String?

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
            Text("Muscle-group volume vs plan")
        } footer: {
            if let citation = CitationRegistry.citation(forId: "volumeDoseResponse") {
                CitationLink(citation: citation, compact: true)
            }
        }
        .alert("Volume warning", isPresented: Binding(
            get: { volumeWarningMessage != nil },
            set: { if !$0 { volumeWarningMessage = nil } })) {
                Button("OK", role: .cancel) { volumeWarningMessage = nil }
            } message: {
                Text(volumeWarningMessage ?? "")
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
                Text("\(Format.sets(volumeSummary.doneSets)) sets")
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
                Text(row.displayName).font(.subheadline)
                    .accessibilityHidden(true)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(Format.sets(row.doneSets)) sets")
                        .font(.caption).foregroundStyle(.secondary)
                    if warningMessage(for: row) != nil {
                        Button {
                            volumeWarningMessage = warningMessage(for: row)
                        } label: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Volume warning for \(row.displayName)")
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("yourPlan.partVolume.\(row.group.rawValue)")
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

    private func warningMessage(for row: WeekVolumePresenter.PartRow) -> String? {
        switch row.status {
        case .short(let toGo):
            return "\(row.displayName) is \(Format.sets(toGo)) sets below the current minimum. You can add work if that fits your recovery and plan."
        case .high:
            return "\(row.displayName) is above the current recommended range. Consider reducing volume or allowing more recovery before adding more work."
        case .targetMet, .onTrack:
            return nil
        }
    }

    private func barColor(for status: WeekVolumePresenter.PartRow.Status) -> Color {
        switch status {
        case .targetMet, .onTrack: return .green
        case .short: return .orange
        case .high: return .gray
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
        return "\(row.displayName): \(Format.sets(row.doneSets)) sets done, \(Format.sets(row.plannedSets)) planned, \(statusText). Recommended \(Int(row.band.lowerBound.rounded())) to \(Int(row.band.upperBound.rounded()))."
    }
}
