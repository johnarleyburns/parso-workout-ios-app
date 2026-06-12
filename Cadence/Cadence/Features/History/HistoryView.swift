import SwiftUI
import SwiftData
import CadenceCore

/// Unified workout history (field-testing Round 4 A4/A5): strength sessions and
/// cardio workouts merged newest-first in one list. New Workout stays at the top;
/// each row opens the read-only `WorkoutSummaryView` (strength offers Edit). This
/// replaces the strength-only `TrainView` behind Home's "Recent workouts → See all".
struct HistoryView: View {
    /// Home's navigation path — rows push summary routes onto it, and New Workout
    /// / Reuse push the live `WorkoutSession` (→ `SessionView` editor).
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutModel.self) private var active
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \CardioWorkout.start, order: .reverse) private var cardio: [CardioWorkout]

    @State private var sessionToDelete: WorkoutSession?
    @State private var cardioToDelete: CardioWorkout?

    /// Strength + cardio merged newest-first (mirrors
    /// `WorkoutRepository.unifiedHistory`, but over the live `@Query` arrays so the
    /// list updates reactively on insert/delete).
    private var entries: [WorkoutHistoryEntry] {
        let s = sessions.map(WorkoutHistoryEntry.strength)
        let c = cardio.map(WorkoutHistoryEntry.cardio)
        return (s + c).sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section("History") {
                if entries.isEmpty {
                    Text("No workouts yet — start one from Home.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    switch entry {
                    case .strength(let s): strengthRow(s)
                    case .cardio(let c): cardioRow(c)
                    }
                }
            }
        }
        .navigationTitle("History")
        .confirmationDialog("Delete this workout?",
                            isPresented: Binding(get: { sessionToDelete != nil },
                                                 set: { if !$0 { sessionToDelete = nil } }),
                            presenting: sessionToDelete) { session in
            Button("Delete", role: .destructive) {
                try? WorkoutRepository.deleteSession(session, in: context)
                sessionToDelete = nil
            }
        } message: { _ in Text("This removes the session and its sets.") }
        .confirmationDialog("Delete this cardio workout?",
                            isPresented: Binding(get: { cardioToDelete != nil },
                                                 set: { if !$0 { cardioToDelete = nil } }),
                            presenting: cardioToDelete) { c in
            Button("Delete", role: .destructive) {
                try? WorkoutRepository.deleteCardio(c, in: context)
                cardioToDelete = nil
            }
        } message: { _ in Text("This removes the recorded workout.") }
    }

    // MARK: Rows

    private func strengthRow(_ session: WorkoutSession) -> some View {
        Button { path.append(HistorySummaryRoute.strength(session)) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title.isEmpty ? "Workout" : session.title)
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(session.orderedSets.count) sets · \(Format.weightValue(session.totalVolume, unit: .kilograms)) kg volume")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.row")
        .swipeActions(edge: .leading) {
            Button { reuse(session) } label: { Label("Reuse", systemImage: "arrow.clockwise") }
                .tint(.blue)
        }
        .swipeActions {
            Button(role: .destructive) { sessionToDelete = session } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func cardioRow(_ c: CardioWorkout) -> some View {
        Button { path.append(HistorySummaryRoute.cardio(c)) } label: {
            HStack {
                Image(systemName: c.typeValue.symbol).foregroundStyle(.tint).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.typeValue.displayName)
                    Text(c.start.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(Format.duration(c.duration))\(c.distance.map { " · " + Format.distance($0) } ?? "")")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history.cardioRow.\(c.typeValue.rawValue)")
        .swipeActions {
            Button(role: .destructive) { cardioToDelete = c } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Actions

    /// Start a fresh session pre-loaded with a past workout's exercises
    /// (field-testing §04, decision #16).
    private func reuse(_ past: WorkoutSession) {
        if let s = try? WorkoutRepository.reuseSession(from: past, in: context) {
            active.startStrength(s)
            path.append(s)
        }
    }
}
