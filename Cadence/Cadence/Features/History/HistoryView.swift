import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct HistoryView: View {
    @Binding var path: NavigationPath
    /// When embedded in the Progress tab, the parent owns the navigation title.
    var embedded = false

    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutModel.self) private var active
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \CardioWorkout.start, order: .reverse) private var cardio: [CardioWorkout]

    @State private var sessionToDelete: WorkoutSession?
    @State private var cardioToDelete: CardioWorkout?
    @State private var showDeleted = false

    private var deletedSessions: [WorkoutSession] { sessions.filter { $0.deletedAt != nil } }
    private var deletedCardio: [CardioWorkout] { cardio.filter { $0.deletedAt != nil } }

    private var entries: [WorkoutHistoryEntry] {
        HistoryPresenter.entries(sessions: sessions, cardio: cardio, showDeleted: showDeleted)
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
                    // The nav title or the Progress tab already says "History".
                    if showDeleted {
                        Text("Deleted")
                    }
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
        .modifier(HistoryChrome(embedded: embedded))
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
        HStack(spacing: 12) {
            Button { Haptics.selection(); path.append(HistorySummaryRoute.strength(session.id)) } label: {
                HStack {
                    Image(systemName: session.symbol).foregroundStyle(.tint).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(session.title.isEmpty ? String(localized: "Workout") : session.title)
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

            if session.deletedAt != nil {
                Button { restore(session) } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.green)
                .accessibilityIdentifier("history.restore")
            }
        }
        .accessibilityIdentifier("session.row")
        .swipeActions(edge: .leading) {
            if session.deletedAt != nil {
                Button { restore(session) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                    .tint(.green)
                    .accessibilityIdentifier("history.restoreSwipe")
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
        HStack(spacing: 12) {
            Button { Haptics.selection(); path.append(HistorySummaryRoute.cardio(c.id)) } label: {
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
                        if c.originValue == .healthKitImported {
                            let origin = HealthKitWorkoutOriginPresenter.label(for: c.healthKitProvenance)
                            Text(origin.primary)
                                .font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(origin.accessibilityLabel)
                        }
                        Text("\(Format.duration(c.duration))\(c.distance.map { " · " + Format.distance($0) } ?? "")")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if c.deletedAt != nil {
                Button { restoreCardio(c) } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.green)
                .accessibilityIdentifier("history.restore")
            }
        }
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
        guard active.liveWorkout.active == nil else { return }
        if let s = try? WorkoutRepository.reuseSession(from: past, in: context) {
            if active.startStrength(s) {
                path.append(HistorySummaryRoute.strengthFocused(s.id, nil))
            } else {
                s.deletedAt = Date()
            }
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

/// Standalone History owns its title; the Progress tab owns title and backdrop,
/// so the embedded list adds neither (a nested title reset the Progress tab).
private struct HistoryChrome: ViewModifier {
    let embedded: Bool
    func body(content: Content) -> some View {
        if embedded {
            content.scrollContentBackground(.hidden)
        } else {
            content.navigationTitle("History")
        }
    }
}
