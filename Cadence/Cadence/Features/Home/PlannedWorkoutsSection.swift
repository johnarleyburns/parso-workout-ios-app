import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct HomePlannedWorkoutsSection: View {
    let records: [ScheduledWorkout]
    let onOpenAll: () -> Void
    let onStart: (ScheduledWorkout) -> Void

    private var items: [PlannedWorkoutsPresenter.Item] { records.map(Self.item) }
    private var today: [PlannedWorkoutsPresenter.Item] { PlannedWorkoutsPresenter.today(items) }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardHeadingSpacing) {
            Text("Planned Workouts").font(.headline)
            if today.isEmpty {
                Text("No workouts planned for today.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(today) { item in
                    if let record = records.first(where: { $0.id == item.id }) {
                        plannedRow(item, record: record)
                    }
                }
            }
            if PlannedWorkoutsPresenter.showsMore(items) {
                Divider().padding(.top, 4)
                Button(action: onOpenAll) {
                    HStack {
                        Text("Show more…")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundStyle(.tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.planned.showMore")
            }
        }
        .padding(LayoutMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .teal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.plannedWorkouts")
    }

    private func plannedRow(_ item: PlannedWorkoutsPresenter.Item,
                            record: ScheduledWorkout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "calendar").font(.caption).foregroundStyle(.teal)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.subheadline.weight(.medium))
                    Text(item.detail).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.status == .started ? "IN PROGRESS" : "SCHEDULED")
                    .font(.caption2.weight(.bold)).foregroundStyle(.teal)
            }
            CadenceActionButton(title: item.status == .started ? "Resume Workout" : "Start This Workout",
                                systemImage: item.status == .started ? "arrow.clockwise" : "play.fill",
                                action: { onStart(record) })
                .accessibilityIdentifier("home.planned.start.\(record.id.uuidString)")
        }
        .padding(.vertical, 6)
    }

    static func item(_ record: ScheduledWorkout) -> PlannedWorkoutsPresenter.Item {
        let detail: String
        if let plan = try? ScheduledWorkoutStore.decode(record.payloadData,
                                                        version: record.payloadVersion) {
            let sets = plan.exercises.reduce(0) { $0 + $1.sets.count }
            detail = "\(plan.exercises.count) exercise\(plan.exercises.count == 1 ? "" : "s") · \(sets) sets"
        } else {
            detail = "Workout plan"
        }
        return PlannedWorkoutsPresenter.Item(id: record.id, date: record.scheduledDate,
                                             title: record.title, detail: detail,
                                             status: record.status)
    }
}

struct PlannedWorkoutsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ScheduledWorkout.scheduledDate),
                  SortDescriptor(\ScheduledWorkout.title)])
    private var records: [ScheduledWorkout]
    @State private var rescheduleRecord: ScheduledWorkout?

    var body: some View {
        List {
            let items = records.map(HomePlannedWorkoutsSection.item)
            let today = PlannedWorkoutsPresenter.today(items)
            let todayIDs = Set(today.map(\.id))
            let future = PlannedWorkoutsPresenter.todayAndFuture(items).filter { !todayIDs.contains($0.id) }
            let overdue = PlannedWorkoutsPresenter.overdue(items)
            if !today.isEmpty { itemSection("Today", items: today) }
            if !future.isEmpty { itemSection("Upcoming", items: future) }
            if !overdue.isEmpty { itemSection("Past planned workouts", items: overdue) }
            if today.isEmpty && future.isEmpty && overdue.isEmpty {
                ContentUnavailableView("No planned workouts", systemImage: "calendar",
                                       description: Text("Schedule a workout from Workout Plan View."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Planned Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $rescheduleRecord) { record in
            ScheduleWorkoutSheet(title: record.title) { date in
                _ = try ScheduledWorkoutStore.reschedule(recordID: record.id,
                                                         to: date,
                                                         in: context)
            }
        }
    }

    @ViewBuilder
    private func itemSection(_ title: String, items: [PlannedWorkoutsPresenter.Item]) -> some View {
        Section(title) {
            ForEach(items) { item in
                if let record = records.first(where: { $0.id == item.id }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "calendar").foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.headline)
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.status == .started ? "IN PROGRESS" : "SCHEDULED")
                                .font(.caption2.weight(.bold)).foregroundStyle(.teal)
                        }
                        HStack {
                            Button(item.status == .started ? "Resume" : "Start") {
                                guard let plan = try? ScheduledWorkoutStore.decode(record.payloadData,
                                                                                   version: record.payloadVersion) else { return }
                                NotificationCenter.default.post(
                                    name: .scheduledWorkoutStartRequested,
                                    object: ScheduledWorkoutStartRequest(recordID: record.id, plan: plan))
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Reschedule") { rescheduleRecord = record }
                                .buttonStyle(.bordered)
                            Button("Delete", role: .destructive) {
                                _ = try? ScheduledWorkoutStore.cancel(recordID: record.id, in: context)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("plannedWorkout.\(record.id.uuidString)")
                }
            }
        }
    }
}

struct ScheduledWorkoutStartRequest {
    let recordID: UUID
    let plan: EditablePlan
}

extension Notification.Name {
    static let scheduledWorkoutStartRequested = Notification.Name("scheduledWorkout.startRequested")
}
