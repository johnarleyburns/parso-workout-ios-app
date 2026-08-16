import SwiftUI
import CadenceFeatures

struct HomeWeekDashboardSection: View {
    let dashboard: HomeDashboardState
    @Binding var volumeExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week").font(.headline)
            progressRow(id: "home.week.strength", title: "Strength", value: dashboard.strength.displayText, progress: dashboard.strength.normalized, tint: dashboard.strength.isAtOrAboveTarget ? .green : .yellow)
            progressRow(id: "home.week.cardio", title: "Cardio", value: dashboard.cardio.displayText, progress: dashboard.cardio.normalized, tint: dashboard.cardio.isAtOrAboveTarget ? .green : .yellow)
            progressRow(id: "home.week.volume", title: "Volume", value: dashboard.volumeCoverage.displayText, progress: dashboard.volumeCoverage.normalized, tint: dashboard.volumeCoverage.isAtOrAboveTarget ? .green : .yellow)
            Button(volumeExpanded ? "Show less" : "Show more…") {
                withAnimation { volumeExpanded.toggle() }
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier(volumeExpanded ? "home.week.showLess" : "home.week.showMore")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .green)
    }

    private func progressRow(id: String, title: String, value: String,
                            progress: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline).foregroundStyle(tint)
                Spacer()
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            ProgressView(value: progress).tint(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}
