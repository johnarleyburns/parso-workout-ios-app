import SwiftUI
import CadenceCore
import CadenceFeatures

/// One tappable Today recommendation (strength or cardio) on the watch launcher.
struct WatchRecommendationRow: View {
    let row: WatchTodayRecommendations.Row
    let onStart: () -> Void

    var body: some View {
        let isStrength = row.modality == .strength
        let session = row.session
        let detail: String
        if isStrength {
            detail = session.exerciseNames.prefix(3).joined(separator: " · ")
        } else {
            detail = [session.durationMinutes.map { "\($0) min" }, session.zone.map { "Z\($0)" }]
                .compactMap { $0 }.joined(separator: " · ")
        }
        let title = session.label.isEmpty ? (isStrength ? "Strength" : "Cardio") : session.label
        return Button(action: onStart) {
            VStack(alignment: .leading, spacing: 2) {
                if row.isAlsoPlanned {
                    Text("Also planned today").font(.caption2.weight(.bold)).foregroundStyle(WatchTone.gold)
                } else {
                    Text("Today").font(.caption2.weight(.bold)).foregroundStyle(isStrength ? WatchTone.accent : .teal)
                }
                Label(title, systemImage: isStrength ? "dumbbell.fill" : "figure.run").font(.footnote.weight(.semibold)).lineLimit(2)
                if !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                if let note = session.adviceNote { Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isStrength ? Color(red: 0.08, green: 0.35, blue: 0.2) : Color(red: 0.05, green: 0.25, blue: 0.3)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Start \(title)"))
        .accessibilityIdentifier(row.accessibilityIdentifier)
    }
}
