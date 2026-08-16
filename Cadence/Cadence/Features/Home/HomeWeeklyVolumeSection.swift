import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeWeeklyVolumeSection: View {
    let rows: [HomeDashboardState.VolumeRow]
    @Binding var explanationExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly Volume").font(.headline)
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(row.displayName).frame(width: 82, alignment: .leading)
                    ProgressView(value: row.normalized).tint(tint(for: row))
                    VStack(alignment: .trailing) {
                        Text("\(formattedSets(row.sets)) sets")
                            .font(.caption.weight(.semibold))
                        if row.status == .aboveRecoveryRange {
                            Label("Above recovery range", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.displayName)
                .accessibilityValue("\(formattedSets(row.sets)) sets, \(row.rangeStatus)")
                .accessibilityIdentifier("home.volume.\(row.part.rawValue)")
            }
            Button(explanationExpanded ? "Show less" : "Show more") {
                withAnimation { explanationExpanded.toggle() }
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier(explanationExpanded ? "home.volume.showLess" : "home.volume.showMore")
            if explanationExpanded {
                Text("Productive volume runs from the experience-scaled starting range to the productive ceiling. Below that range may provide less training stimulus; above the recovery range may make recovery harder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                CitationLink(citation: CitationRegistry.volumeDoseResponse, compact: true)
                    .accessibilityIdentifier("home.volume.science")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .orange)
        .accessibilityIdentifier("home.volume")
    }

    private func formattedSets(_ sets: Double) -> String {
        sets.formatted(.number.precision(.fractionLength(sets.rounded() == sets ? 0 : 1)))
    }

    private func tint(for row: HomeDashboardState.VolumeRow) -> Color {
        switch row.status {
        case .belowStartingRange: return .yellow
        case .productive: return .green
        case .aboveRecoveryRange: return .red
        }
    }
}
