import SwiftUI
import CadenceCore
import CadenceFeatures

/// One compact card with an independently startable row per modality.
struct HomeTodayRecommendationsCard: View {
    let rows: [TodayRecommendationRow]
    let onStart: (CoachSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                if row.id != rows.first?.id { Divider() }
                rowView(row)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("home.todayRecommendations")
    }

    private func rowView(_ row: TodayRecommendationRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(row.modalityLabel, systemImage: row.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CadenceTheme.accent)
                Spacer(minLength: 8)
                Text(row.badge.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(.headline)
                    if let duration = row.durationText {
                        Text(duration).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button { onStart(row.session) } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(CadenceTheme.accent)
                .accessibilityLabel(Text("Start \(row.modalityLabel): \(row.title)"))
                .accessibilityIdentifier(row.startIdentifier)
            }
            if !row.rationale.isEmpty {
                Text(row.rationale).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            if !row.citationIds.isEmpty {
                CoachSourcesLink(
                    citationIds: row.citationIds,
                    identifier: "home.todayRecommendation.\(row.modality.rawValue).science")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
