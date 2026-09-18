import SwiftUI
import CadenceCore
import CadenceFeatures

/// One compact Today surface for completed workouts and explicitly scheduled
/// workouts. Recommendations never appear here unless the user scheduled them.
struct HomeMyWorkoutsSection: View {
    let completed: [WorkoutsTodayPresenter.Row]
    let scheduled: [ScheduledWorkout]
    let onOpenCompleted: (WorkoutsTodayPresenter.Row) -> Void
    let onStartScheduled: (ScheduledWorkout) -> Void
    let onShowMorePlanned: () -> Void

    private var plannedItems: [PlannedWorkoutsPresenter.Item] { scheduled.map(HomePlannedWorkoutsSection.item) }
    private var todayItems: [PlannedWorkoutsPresenter.Item] { PlannedWorkoutsPresenter.today(plannedItems) }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardHeadingSpacing) {
            Text("My Workouts").font(.headline)
            if completed.isEmpty && todayItems.isEmpty {
                Text("Nothing completed or planned for today.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(completed) { row in
                HomeWeekWorkoutRow(row: row) { onOpenCompleted(row) }
            }
            ForEach(todayItems) { item in
                if let record = scheduled.first(where: { $0.id == item.id }) {
                    plannedRow(item, record: record)
                }
            }
            if PlannedWorkoutsPresenter.showsMore(plannedItems) {
                Divider().padding(.top, 4)
                Button(action: onShowMorePlanned) {
                    HStack {
                        Text("Show more…")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundStyle(.tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.myWorkouts.showMore")
            }
        }
        .padding(LayoutMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.myWorkouts")
    }

    private func plannedRow(_ item: PlannedWorkoutsPresenter.Item,
                            record: ScheduledWorkout) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").font(.caption).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.subheadline.weight(.medium))
                Text(item.detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text("PLANNED")
                .font(.caption2.weight(.bold)).foregroundStyle(.teal)
            Button { onStartScheduled(record) } label: {
                Image(systemName: "play.fill").font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Start planned workout")
            .accessibilityIdentifier("home.myWorkouts.start.\(record.id.uuidString)")
        }
        .padding(.vertical, 7)
    }
}

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
