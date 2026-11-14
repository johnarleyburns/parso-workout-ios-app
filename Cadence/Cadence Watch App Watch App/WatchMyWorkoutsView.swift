import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// My Workouts page (swipe left from This Week): today's planned sessions, then recent history.
struct WatchMyWorkoutsView: View {
    let plan: WatchSync.TodayPlan?
    /// Watch-owned cardio completions are visible immediately; the phone snapshot
    /// replaces them after acknowledgement.
    var pendingCardioCompletions: [WatchCardioCompletion] = []
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
                    WatchMyWorkoutDestination(row: row, pendingCardioCompletions: pendingCardioCompletions)
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
        .task(id: "\(cardioHistoryRevision)|\(pendingCardioCompletions.map(\.id.uuidString).joined(separator: ","))") { load() }
        .onReceive(NotificationCenter.default.publisher(for: WatchLocalHistoryMutation.name)) { _ in
            // Strength is already in the Watch SwiftData store; refresh its local
            // projection immediately rather than waiting for the phone round trip.
            load()
        }
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
        let mirrored = ((try? context.fetch(cardioDescriptor)) ?? []).map {
            WatchMyWorkouts.CardioInput(id: $0.id, title: $0.title, type: $0.typeRaw, start: $0.start,
                                        end: $0.end, distanceMeters: $0.distanceMeters,
                                        importLabel: $0.importLabel,
                                        hasRichSummary: $0.summaryData.flatMap(WatchWorkoutHistorySummary.decode) != nil)
        }
        let mirroredIDs = Set(mirrored.map(\.id))
        let local = pendingCardioCompletions
            .filter { !mirroredIDs.contains($0.id) }
            .map {
                WatchMyWorkouts.CardioInput(id: $0.id, title: $0.title ?? $0.type.displayName,
                                            type: $0.type.rawValue, start: $0.start, end: $0.end,
                                            distanceMeters: $0.distanceMeters,
                                            importLabel: String(localized: "Saved on Watch"), hasRichSummary: true)
            }
        cardio = mirrored + local
    }
}
