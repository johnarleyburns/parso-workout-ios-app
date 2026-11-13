import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct PlannedWorkoutRowInput: Sendable {
    let id: UUID
    let date: Date
    let title: String
    let payloadData: Data
    let payloadVersion: Int
    let status: ScheduledWorkoutStatus
}

/// Namespace for the planned-workout row mapping helpers used by Today.
enum HomePlannedWorkoutsSection {
    nonisolated static func rowInput(_ record: ScheduledWorkout) -> PlannedWorkoutRowInput {
        PlannedWorkoutRowInput(id: record.id,
                               date: record.scheduledDate,
                               title: record.title,
                               payloadData: record.payloadData,
                               payloadVersion: record.payloadVersion,
                               status: record.status)
    }

    nonisolated static func item(_ input: PlannedWorkoutRowInput) -> PlannedWorkoutsPresenter.Item {
        let detail: String
        let day = input.date.formatted(date: .abbreviated, time: .omitted)
        let time = ScheduledWorkoutDate.hasExplicitTime(input.date)
            ? "\(day) · \(input.date.formatted(date: .omitted, time: .shortened))"
            : day
        if let cardio = try? ScheduledWorkoutStore.decodeCardioType(input.payloadData,
                                                                    version: input.payloadVersion) {
            detail = [time, cardio.displayName].joined(separator: " · ")
        } else if let plan = try? ScheduledWorkoutStore.decode(input.payloadData,
                                                               version: input.payloadVersion) {
            let sets = plan.exercises.reduce(0) { $0 + $1.sets.count }
            let body = String(localized: "Exercises: \(plan.exercises.count) · Sets: \(sets)")
            detail = [time, body].joined(separator: " · ")
        } else {
            detail = [time, String(localized: "Workout plan")].joined(separator: " · ")
        }
        return PlannedWorkoutsPresenter.Item(id: input.id, date: input.date,
                                             title: input.title, detail: detail,
                                             status: input.status)
    }

    nonisolated static func item(_ record: ScheduledWorkout) -> PlannedWorkoutsPresenter.Item {
        item(rowInput(record))
    }

    /// Flattens a scheduled workout into `ScheduledWorkoutWatchBridge`'s pure,
    /// SwiftData-free input shape (issue: surface manually scheduled workouts
    /// on Watch Today).
    nonisolated static func watchBridgeInput(_ record: ScheduledWorkout) -> ScheduledWorkoutWatchBridge.Input {
        ScheduledWorkoutWatchBridge.Input(id: record.id, date: record.scheduledDate, title: record.title,
                                          payloadData: record.payloadData, payloadVersion: record.payloadVersion,
                                          status: record.status)
    }
}

struct PlannedWorkoutsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ScheduledWorkout.scheduledDate),
                  SortDescriptor(\ScheduledWorkout.title)])
    private var records: [ScheduledWorkout]
    @State private var rescheduleRecord: ScheduledWorkout?
    @State private var projectedItems: [PlannedWorkoutsPresenter.Item] = []
    @State private var failedStartRecordID: UUID?

    private var projectionSignature: [ScheduledWorkoutTaskSignature] {
        records.map {
            ScheduledWorkoutTaskSignature(id: $0.id,
                                          scheduledDate: $0.scheduledDate,
                                          updatedAt: $0.updatedAt,
                                          statusRaw: $0.statusRaw,
                                          payloadVersion: $0.payloadVersion)
        }
    }

    var body: some View {
        List {
            let items = projectedItems
            let today = PlannedWorkoutsPresenter.today(items)
            let todayIDs = Set(today.map(\.id))
            let future = PlannedWorkoutsPresenter.todayAndFuture(items).filter { !todayIDs.contains($0.id) }
            let overdue = PlannedWorkoutsPresenter.overdue(items)
            if !today.isEmpty { itemSection(String(localized: "Today"), items: today) }
            if !future.isEmpty { itemSection(String(localized: "Upcoming"), items: future) }
            if !overdue.isEmpty { itemSection(String(localized: "Past planned workouts"), items: overdue) }
            if today.isEmpty && future.isEmpty && overdue.isEmpty {
                ContentUnavailableView("No planned workouts", systemImage: "calendar",
                                       description: Text("Schedule a workout from Workout Plan View."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Planned Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: projectionSignature) {
            let inputs = records.map(HomePlannedWorkoutsSection.rowInput)
            let projected = await Task.detached(priority: .utility) {
                inputs.map(HomePlannedWorkoutsSection.item)
            }.value
            guard !Task.isCancelled else { return }
            projectedItems = projected
        }
        .sheet(item: $rescheduleRecord) { record in
            ScheduleWorkoutSheet(title: record.title) { date in
                _ = try ScheduledWorkoutStore.reschedule(recordID: record.id,
                                                         to: date,
                                                         in: context)
            }
        }
        .alert("Couldn't open this workout", isPresented: Binding(
            get: { failedStartRecordID != nil },
            set: { if !$0 { failedStartRecordID = nil } })) {
                Button("Try Again") {
                    if let id = failedStartRecordID,
                       let record = records.first(where: { $0.id == id }) {
                        start(record)
                    }
                }
                Button("Close", role: .cancel) { failedStartRecordID = nil }
            } message: {
                Text("The saved workout could not be read. Try again, or reschedule/delete it from this list if the problem continues.")
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
                                start(record)
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

    private func start(_ record: ScheduledWorkout) {
        failedStartRecordID = nil
        if let cardio = try? ScheduledWorkoutStore.decodeCardioType(record.payloadData,
                                                                    version: record.payloadVersion) {
            NotificationCenter.default.post(
                name: .scheduledCardioStartRequested,
                object: ScheduledCardioStartRequest(recordID: record.id, type: cardio))
            return
        }
        guard let plan = try? ScheduledWorkoutStore.decode(record.payloadData,
                                                           version: record.payloadVersion) else {
            failedStartRecordID = record.id
            return
        }
        NotificationCenter.default.post(
            name: .scheduledWorkoutStartRequested,
            object: ScheduledWorkoutStartRequest(recordID: record.id, plan: plan))
    }
}

struct ScheduledWorkoutStartRequest {
    let recordID: UUID
    let plan: EditablePlan
}

struct ScheduledCardioStartRequest {
    let recordID: UUID
    let type: CardioType
}

extension Notification.Name {
    static let scheduledWorkoutStartRequested = Notification.Name("scheduledWorkout.startRequested")
    static let scheduledCardioStartRequested = Notification.Name("scheduledCardio.startRequested")
}
