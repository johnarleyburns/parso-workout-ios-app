import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// My Workouts page (swipe left from This Week): today's planned sessions, then recent history.
struct WatchMyWorkoutsView: View {
    let plan: WatchSync.TodayPlan?
    /// Bumped by the manager only after a phone cardio-history snapshot is durably stored.
    var cardioHistoryRevision: Int = 0
    var distanceUnit: DistanceUnitPreference = .kilometers
    @Environment(\.modelContext) private var context
    @State private var history: [WatchMyWorkouts.HistoryInput] = []
    @State private var cardio: [WatchMyWorkouts.CardioInput] = []

    private var rows: [WatchMyWorkoutRow] { WatchMyWorkouts.rows(plan: plan, history: history, cardio: cardio) }

    var body: some View {
        List {
            if rows.isEmpty {
                Text("No workouts yet. Planned and completed workouts appear here.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                NavigationLink {
                    WatchMyWorkoutDetailView(row: row, distanceUnit: distanceUnit)
                } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.status == .planned ? "Planned" : "Done")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(row.status == .planned ? WatchTone.accent : .secondary)
                    Text(row.title).font(.footnote.weight(.semibold)).lineLimit(2)
                    if let date = row.date {
                        subtitle(row, date: date)
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let origin = row.originLabel {
                            Text(origin).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        }
                    } else if !row.exerciseNames.isEmpty {
                        Text(row.exerciseNames.prefix(3).joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("My Workouts")
        .accessibilityIdentifier("watch.myWorkouts")
        .task(id: cardioHistoryRevision) { load() }
    }

    private func subtitle(_ row: WatchMyWorkoutRow, date: Date) -> Text {
        let day = Text(date, format: .dateTime.month().day())
        if row.showsSetCount { return day + Text(verbatim: " · ") + Text("\(row.setCount) sets") }
        if let summary = row.cardioSummary(distanceUnit: distanceUnit) { return day + Text(verbatim: " · \(summary)") }
        return day
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
        var cardioDescriptor = FetchDescriptor<WatchCardioHistoryRecord>(
            sortBy: [SortDescriptor(\.start, order: .reverse)])
        cardioDescriptor.fetchLimit = WatchSync.CardioHistorySnapshot.maxLiveItems
        cardio = ((try? context.fetch(cardioDescriptor)) ?? []).map {
            WatchMyWorkouts.CardioInput(id: $0.id, title: $0.title, type: $0.typeRaw, start: $0.start,
                                        end: $0.end, distanceMeters: $0.distanceMeters,
                                        importLabel: $0.importLabel)
        }
    }
}

/// Summary/detail for a planned or completed workout row. Cardio rows are phone-owned and read-only.
struct WatchMyWorkoutDetailView: View {
    let row: WatchMyWorkoutRow
    var distanceUnit: DistanceUnitPreference = .kilometers
    @Environment(\.modelContext) private var context
    @State private var lines: [String] = []

    var body: some View {
        List {
            Text(row.status == .planned ? "Planned" : "Done")
                .font(.caption2.weight(.bold))
                .foregroundStyle(row.status == .planned ? WatchTone.accent : .secondary)
            if let date = row.date {
                Text(date, format: .dateTime.month().day().year())
                    .font(.caption2).foregroundStyle(.secondary)
                if row.showsSetCount {
                    Text("\(row.setCount) sets").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if case .cardio = row.source {
                if let summary = row.cardioSummary(distanceUnit: distanceUnit) {
                    Text(summary).font(.footnote)
                }
                if let origin = row.originLabel {
                    Text(origin).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Recorded on your iPhone. Manage it there.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.footnote)
            }
        }
        .navigationTitle(row.title)
        .task { load() }
    }

    private func load() {
        switch row.source {
        case .planned: lines = row.exerciseNames
        case .cardio: lines = []
        case .strength(let id):
            let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
            guard let session = (try? context.fetch(descriptor))?.first else { return }
            lines = session.exercisesInOrder.map { ex in
                let n = session.orderedSets.filter { $0.exercise?.id == ex.id && !$0.isWarmup && $0.isOwnerSet }.count
                return "\(ex.name) · \(n) sets"
            }
        }
    }
}
