import SwiftUI
import SwiftData
import CadenceCore

/// A history row's read-only summary destination (field-testing Round 4 A5).
/// Wraps the `@Model` row (already `Hashable`) so the big `WorkoutSummaryData`
/// value type needn't be `Hashable`.
enum HistorySummaryRoute: Hashable {
    case strength(WorkoutSession)
    case cardio(CardioWorkout)
}

struct HistoryView: View {
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutModel.self) private var active
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \CardioWorkout.start, order: .reverse) private var cardio: [CardioWorkout]

    @State private var sessionToDelete: WorkoutSession?
    @State private var cardioToDelete: CardioWorkout?
    @State private var showDeleted = false

    private var activeSessions: [WorkoutSession] { sessions.filter { $0.deletedAt == nil } }
    private var deletedSessions: [WorkoutSession] { sessions.filter { $0.deletedAt != nil } }
    private var activeCardio: [CardioWorkout] { cardio.filter { $0.deletedAt == nil } }
    private var deletedCardio: [CardioWorkout] { cardio.filter { $0.deletedAt != nil } }

    private var entries: [WorkoutHistoryEntry] {
        let s = (showDeleted ? deletedSessions : activeSessions).map(WorkoutHistoryEntry.strength)
        let c = (showDeleted ? deletedCardio : activeCardio).map(WorkoutHistoryEntry.cardio)
        return (s + c).sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                if entries.isEmpty {
                    Text(showDeleted ? "No deleted workouts." : "No workouts yet — start one from Home.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    switch entry {
                    case .strength(let s): strengthRow(s)
                    case .cardio(let c): cardioRow(c)
                    }
                }
            } header: {
                HStack {
                    Text(showDeleted ? "Deleted" : "History")
                    Spacer()
                    if !deletedSessions.isEmpty || !deletedCardio.isEmpty {
                        Button(showDeleted ? "Back" : "View Deleted") {
                            withAnimation { showDeleted.toggle() }
                        }
                        .font(.caption)
                        .accessibilityIdentifier("history.toggleDeleted")
                    }
                }
            } footer: {
                if showDeleted {
                    Text("Swipe to restore a deleted workout.")
                }
            }
        }
        .navigationTitle("History")
        .confirmationDialog("Delete this workout?",
                            isPresented: Binding(get: { sessionToDelete != nil },
                                                 set: { if !$0 { sessionToDelete = nil } }),
                            presenting: sessionToDelete) { session in
            Button("Delete", role: .destructive) {
                try? WorkoutRepository.softDeleteSession(session, in: context)
                sessionToDelete = nil
            }
        } message: { _ in Text("This removes the session. You can restore it from View Deleted.") }
        .confirmationDialog("Delete this cardio workout?",
                            isPresented: Binding(get: { cardioToDelete != nil },
                                                 set: { if !$0 { cardioToDelete = nil } }),
                            presenting: cardioToDelete) { c in
            Button("Delete", role: .destructive) {
                try? WorkoutRepository.softDeleteCardio(c, in: context)
                cardioToDelete = nil
            }
        } message: { _ in Text("This removes the cardio workout. You can restore it from View Deleted.") }
    }

    // MARK: Rows

    private func strengthRow(_ session: WorkoutSession) -> some View {
        Button { Haptics.selection(); path.append(HistorySummaryRoute.strength(session)) } label: {
            HStack {
                Image(systemName: session.symbol).foregroundStyle(.tint).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(session.title.isEmpty ? "Workout" : session.title)
                        if session.isLogged { LoggedTag() }
                        if session.deletedAt != nil { DeletedTag() }
                    }
                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(session.orderedSets.count) sets · \(Format.weightValue(session.totalVolume, unit: .kilograms)) kg volume")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.row")
        .swipeActions(edge: .leading) {
            if session.deletedAt != nil {
                Button { restore(session) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                    .tint(.green)
                    .accessibilityIdentifier("history.restore")
            } else {
                Button { reuse(session) } label: { Label("Reuse", systemImage: "arrow.clockwise") }
                    .tint(.blue)
            }
        }
        .swipeActions {
            if session.deletedAt != nil {
                Button(role: .destructive) {
                    try? WorkoutRepository.deleteSession(session, in: context)
                } label: { Label("Purge", systemImage: "trash.slash") }
                    .accessibilityIdentifier("history.purge")
            } else {
                Button(role: .destructive) { sessionToDelete = session } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func cardioRow(_ c: CardioWorkout) -> some View {
        Button { Haptics.selection(); path.append(HistorySummaryRoute.cardio(c)) } label: {
            HStack {
                Image(systemName: c.typeValue.symbol).foregroundStyle(.tint).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(c.displayTitle)
                        if c.isLogged { LoggedTag() }
                        if c.deletedAt != nil { DeletedTag() }
                    }
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
            if c.deletedAt != nil {
                Button(role: .destructive) {
                    try? WorkoutRepository.deleteCardio(c, in: context)
                } label: { Label("Purge", systemImage: "trash.slash") }
            } else {
                Button(role: .destructive) { cardioToDelete = c } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if c.deletedAt != nil {
                Button { restoreCardio(c) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                    .tint(.green)
            }
        }
    }

    // MARK: Actions

    private func reuse(_ past: WorkoutSession) {
        if let s = try? WorkoutRepository.reuseSession(from: past, in: context) {
            active.startStrength(s)
            path.append(s)
        }
    }

    private func restore(_ s: WorkoutSession) {
        try? WorkoutRepository.restoreSession(s, in: context)
    }

    private func restoreCardio(_ c: CardioWorkout) {
        try? WorkoutRepository.restoreCardio(c, in: context)
    }
}

struct DeletedTag: View {
    var body: some View {
        Text("Deleted")
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.red.opacity(0.15), in: Capsule())
            .foregroundStyle(.red)
            .accessibilityLabel("Deleted")
    }
}
