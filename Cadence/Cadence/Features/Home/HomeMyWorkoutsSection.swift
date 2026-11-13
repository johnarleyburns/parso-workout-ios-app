import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeMyHistorySection: View {
    let entries: [TodayActivityPresenter.Entry]
    let onOpen: (TodayActivityPresenter.Entry) -> Void
    let onShowMore: () -> Void
    @State private var expanded = false

    private var orderedEntries: [TodayActivityPresenter.Entry] {
        entries.sorted { $0.occurredAt > $1.occurredAt }
    }

    private var visibleEntries: [TodayActivityPresenter.Entry] {
        expanded ? orderedEntries : Array(orderedEntries.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardHeadingSpacing) {
            Text("My History").font(.headline)
            if visibleEntries.isEmpty {
                Text("No workouts logged this week.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(visibleEntries) { entry in
                    HomeWeekWorkoutRow(entry: entry) { onOpen(entry) }
                }
            }
            if !orderedEntries.isEmpty {
                Divider().padding(.top, 4)
                Button {
                    if expanded {
                        onShowMore()
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) { expanded = true }
                    }
                } label: {
                    HStack {
                        Text(expanded ? "View full history" : "Show more…")
                        Spacer()
                        Image(systemName: expanded ? "chevron.right" : "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(expanded ? "home.history.fullHistory" : "home.history.showMore")
            }
        }
        .padding(LayoutMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .blue)
        .accessibilityIdentifier("home.myHistory")
    }
}
