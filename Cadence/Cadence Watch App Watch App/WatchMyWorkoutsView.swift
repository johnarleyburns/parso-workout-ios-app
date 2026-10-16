import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// My Workouts page (swipe left from This Week): today's planned sessions, then recent history.
struct WatchMyWorkoutsView: View {
    let plan: WatchSync.TodayPlan?
    @Environment(\.modelContext) private var context
    @State private var history: [WatchMyWorkouts.HistoryInput] = []

    private var rows: [WatchMyWorkoutRow] { WatchMyWorkouts.rows(plan: plan, history: history) }

    var body: some View {
        List {
            if rows.isEmpty {
                Text("No workouts yet. Planned and completed workouts appear here.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.status == .planned ? "Planned" : "Done")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(row.status == .planned ? WatchTone.accent : .secondary)
                    Text(row.title).font(.footnote.weight(.semibold)).lineLimit(2)
                    if let date = row.date {
                        (Text(date, format: .dateTime.month().day()) + Text(verbatim: " · ") + Text("\(row.setCount) sets"))
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if !row.exerciseNames.isEmpty {
                        Text(row.exerciseNames.prefix(3).joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .listStyle(.plain)
        .navigationTitle("My Workouts")
        .accessibilityIdentifier("watch.myWorkouts")
        .task { load() }
    }

    private func load() {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 60
        let sessions = (try? context.fetch(descriptor)) ?? []
        history = sessions.filter { $0.endedAt != nil || $0.isLogged }.map {
            WatchMyWorkouts.HistoryInput(id: $0.id, title: $0.title, date: $0.date,
                                         setCount: $0.completedOwnerWorkingSetCount)
        }
    }
}
