import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct HistoryView: View {
    @Binding var path: NavigationPath
    /// When embedded in the Progress tab, the parent owns the navigation title.
    var embedded = false

    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutModel.self) private var active

    @State private var sessionToDelete: WorkoutSession?
    @State private var cardioToDelete: CardioWorkout?
    @State private var paging: HistoryPagingState?
    @State private var showExport = false

    private var showDeleted: Bool { paging?.visibility == .deleted }

    private var entries: [WorkoutHistoryEntry] { paging?.entries ?? [] }

    private var sessions: [WorkoutSession] {
        entries.compactMap { if case .strength(let s) = $0 { s } else { nil } }
    }
    private var cardio: [CardioWorkout] {
        entries.compactMap { if case .cardio(let c) = $0 { c } else { nil } }
    }

    private var timelineEntries: [TodayActivityPresenter.Entry] {
        // Deleted rows keep the normal timeline layout; only the presenter's
        // filter changes, so Show Deleted no longer swaps in a different list.
        TodayActivityPresenter.historyEntries(sessions: sessions, cardio: cardio,
                                              includeDeleted: showDeleted)
    }

    var body: some View {
        workoutTimeline
        .modifier(HistoryChrome(embedded: embedded))
        .toolbar {
            if let control = paging?.deletedControl {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation { paging?.toggleDeleted() } } label: {
                        Text(control.title)
                            .font(.subheadline.weight(.semibold))
                    }
                        .accessibilityLabel(control.title)
                        .accessibilityIdentifier("history.toggleDeleted")
                        .accessibilityHint("Switches between active and deleted workouts")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showExport = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                    .accessibilityLabel("Share workout archive")
                    .accessibilityIdentifier("history.export")
                    .accessibilityHint("Exports your complete workout archive")
            }
        }
        .sheet(isPresented: $showExport) {
            NavigationStack {
                ExportView(mode: .exportOnly)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showExport = false }
                        }
                    }
            }
        }
        .task {
            if paging == nil { paging = HistoryPagingState(fetcher: WorkoutHistoryPageFetcher(context: context)) }
            refresh()
        }
        // Any save (new, restored, soft-deleted record) resets to the first page.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in refresh() }
        .confirmationDialog("Delete this workout?",
                            isPresented: Binding(get: { sessionToDelete != nil },
                                                 set: { if !$0 { sessionToDelete = nil } }),
                            presenting: sessionToDelete) { session in
            Button("Delete", role: .destructive) {
                try? WorkoutRepository.softDeleteSession(session, in: context)
                sessionToDelete = nil
                notifyHistoryChanged()
            }
        } message: { _ in Text("This removes the session. You can restore it from the Archive button.") }
        .confirmationDialog("Delete this cardio workout?",
                            isPresented: Binding(get: { cardioToDelete != nil },
                                                 set: { if !$0 { cardioToDelete = nil } }),
                            presenting: cardioToDelete) { c in
            Button("Delete", role: .destructive) {
                try? WorkoutRepository.softDeleteCardio(c, in: context)
                cardioToDelete = nil
                notifyHistoryChanged()
            }
        } message: { _ in Text("This removes the cardio workout. You can restore it from the Archive button.") }
    }

    /// A real `List` (not a `ScrollView`/`VStack`) so `.swipeActions` works --
    /// visually restyled to the same glass card look the plain `VStack` had.
    private var workoutTimeline: some View {
        List {
            Text("My Workouts").font(.headline)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if timelineEntries.isEmpty {
                Text(showDeleted
                     ? "No deleted workouts."
                     : "No workouts yet — start one from Today.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(timelineEntries) { entry in
                    HomeWeekWorkoutRow(entry: entry, showsTimestamp: true) { open(entry) }
                        .contextMenu { timelineActions(for: entry) }
                        .swipeActions(edge: .trailing) {
                            if entry.isDeleted {
                                Button(role: .destructive) { purgeImmediately(entry) } label: {
                                    Label("Delete permanently", systemImage: "trash.slash")
                                }
                            } else {
                                Button(role: .destructive) { deleteImmediately(entry) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if entry.isDeleted {
                                Button { restoreImmediately(entry) } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                showMoreButton
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .padding(LayoutMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .blue)
        .padding(.horizontal)
        .padding(.bottom, CadenceTabBarClearance.scrollContentBottom)
        .accessibilityIdentifier("history.myWorkouts")
    }

    /// Slide-to-delete acts immediately (the row remains recoverable from the
    /// Archive / Show deleted surface). No confirmation dialog on a swipe.
    private func deleteImmediately(_ entry: TodayActivityPresenter.Entry) {
        switch entry.kind {
        case .strength:
            if let session = sessions.first(where: { $0.id == entry.sourceId }) {
                try? WorkoutRepository.softDeleteSession(session, in: context)
            }
        case .cardio:
            if let workout = cardio.first(where: { $0.id == entry.sourceId }) {
                try? WorkoutRepository.softDeleteCardio(workout, in: context)
            }
        }
        notifyHistoryChanged()
    }

    /// Restore is the leading-swipe action while the deleted archive is open.
    private func restoreImmediately(_ entry: TodayActivityPresenter.Entry) {
        switch entry.kind {
        case .strength:
            if let session = sessions.first(where: { $0.id == entry.sourceId }) {
                try? WorkoutRepository.restoreSession(session, in: context)
            }
        case .cardio:
            if let workout = cardio.first(where: { $0.id == entry.sourceId }) {
                try? WorkoutRepository.restoreCardio(workout, in: context)
            }
        }
        notifyHistoryChanged()
    }

    /// Permanent removal is only offered from the already-deleted archive.
    private func purgeImmediately(_ entry: TodayActivityPresenter.Entry) {
        switch entry.kind {
        case .strength:
            if let session = sessions.first(where: { $0.id == entry.sourceId }) {
                try? WorkoutRepository.deleteSession(session, in: context)
            }
        case .cardio:
            if let workout = cardio.first(where: { $0.id == entry.sourceId }) {
                try? WorkoutRepository.deleteCardio(workout, in: context)
            }
        }
        notifyHistoryChanged()
    }

    private func notifyHistoryChanged() {
        NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
    }

    @ViewBuilder private var showMoreButton: some View {
        if paging?.hasMore == true {
            Button { Haptics.selection(); paging?.loadMore() } label: {
                Text("Show \(HistoryPageRequest.pageSize) more")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("history.showMore")
        }
    }

    private func refresh() {
        paging?.reload(deletedCount: (try? WorkoutRepository.deletedHistoryCount(in: context)) ?? 0)
    }

    private func open(_ entry: TodayActivityPresenter.Entry) {
        Haptics.selection()
        switch WorkoutsTodayPresenter.historyRoute(for: entry) {
        case .strength(let id): path.append(HistorySummaryRoute.strength(id))
        case .cardio(let id): path.append(HistorySummaryRoute.cardio(id))
        }
    }

    @ViewBuilder
    private func timelineActions(for entry: TodayActivityPresenter.Entry) -> some View {
        switch entry.kind {
        case .strength:
            if let session = sessions.first(where: { $0.id == entry.sourceId }) {
                if entry.isDeleted {
                    Button { restoreImmediately(entry) } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    Button(role: .destructive) { purgeImmediately(entry) } label: {
                        Label("Delete permanently", systemImage: "trash.slash")
                    }
                } else {
                    Button { reuse(session) } label: { Label("Reuse", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { sessionToDelete = session } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        case .cardio:
            if let workout = cardio.first(where: { $0.id == entry.sourceId }) {
                if entry.isDeleted {
                    Button { restoreImmediately(entry) } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    Button(role: .destructive) { purgeImmediately(entry) } label: {
                        Label("Delete permanently", systemImage: "trash.slash")
                    }
                } else {
                    Button(role: .destructive) { cardioToDelete = workout } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
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
