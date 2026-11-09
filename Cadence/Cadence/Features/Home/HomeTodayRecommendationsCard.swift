import SwiftUI
import CadenceCore
import CadenceFeatures

/// The Today surface always keeps Strength above Cardio. Each modality owns its
/// recommendation and completion state; neither can replace the other.
struct HomeTodayRecommendationsCard: View {
    let rows: [TodayRecommendationRow]
    let completedStrengthTitle: String?
    let completedCardioTitle: String?
    let onStart: (CoachSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section(modality: .strength, completedTitle: completedStrengthTitle)
            section(modality: .cardio, completedTitle: completedCardioTitle)
        }
        .accessibilityIdentifier("home.todayRecommendations")
    }

    private func section(modality: DailyRecommendationModality,
                         completedTitle: String?) -> some View {
        let row = rows.first { $0.modality == modality }
        return VStack(alignment: .leading, spacing: 4) {
            if let completedTitle {
                completionView(modality: modality, title: completedTitle)
            } else if let row {
                rowView(row)
            } else {
                unavailableView(modality: modality)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("home.todayRecommendation.\(modality.rawValue)")
    }

    private func completionView(modality: DailyRecommendationModality, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(modality == .strength ? "Strength Done for Today" : "Cardio Done for Today",
                  systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(CadenceTheme.achievement)
            Text(title).font(.headline)
            Text("Your completed \(modality.rawValue) is recorded for today.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("home.todayRecommendation.\(modality.rawValue).done")
    }

    private func unavailableView(modality: DailyRecommendationModality) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(modality == .strength ? "Suggested Strength for You" : "Suggested Cardio for You",
                  systemImage: modality == .strength ? "dumbbell.fill" : "heart.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(CadenceTheme.accent)
            Text("No \(modality.rawValue) suggestion is available right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
