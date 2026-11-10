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
        TodayActivityPresenter.historyEntries(sessions: sessions, cardio: cardio)
    }

    var body: some View {
        Group {
            if showDeleted {
                legacyDeletedList
            } else {
                workoutTimeline
            }
        }
        .modifier(HistoryChrome(embedded: embedded))
        .toolbar {
            if let control = paging?.deletedControl {
                ToolbarItem(placement: .topBarLeading) {
                    Button(control.title) { withAnimation { paging?.toggleDeleted() } }
                        .accessibilityIdentifier("history.toggleDeleted")
                        .accessibilityHint("Switches between active and deleted workouts")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Export") { showExport = true }
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
            }
        } message: { _ in Text("This removes the session. You can restore it from Show Deleted.") }
        .confirmationDialog("Delete this cardio workout?",
                            isPresented: Binding(get: { cardioToDelete != nil },
                                                 set: { if !$0 { cardioToDelete = nil } }),
                            presenting: cardioToDelete) { c in
            Button("Delete", role: .destructive) {
                try? WorkoutRepository.softDeleteCardio(c, in: context)
                cardioToDelete = nil
            }
        } message: { _ in Text("This removes the cardio workout. You can restore it from Show Deleted.") }
    }

    private var workoutTimeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.cardHeadingSpacing) {
                HStack {
                    Text("My Workouts").font(.headline)
                    Spacer()
                }
                if timelineEntries.isEmpty {
                    Text("No workouts yet — start one from Today.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(timelineEntries) { entry in
                        HomeWeekWorkoutRow(entry: entry) { open(entry) }
                            .contextMenu { timelineActions(for: entry) }
                    }
                    showMoreButton
                }
            }
            .padding(LayoutMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .blue)
            .padding(.horizontal)
            .padding(.bottom, CadenceTabBarClearance.scrollContentBottom)
        }
        .accessibilityIdentifier("history.myWorkouts")
    }

    private var legacyDeletedList: some View {
        List {
            Section {
                if entries.isEmpty {
                    Text("No deleted workouts.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    switch entry {
                    case .strength(let s): strengthRow(s)
                    case .cardio(let c): cardioRow(c)
                    }
                }
                showMoreButton
            } header: {
                Text("Deleted")
            } footer: {
                if showDeleted {
                    Text("Swipe to restore a deleted workout.")
                }
            }
        }
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
                Button { reuse(session) } label: { Label("Reuse", systemImage: "arrow.clockwise") }
                Button(role: .destructive) { sessionToDelete = session } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        case .cardio:
            if let workout = cardio.first(where: { $0.id == entry.sourceId }) {
                Button(role: .destructive) { cardioToDelete = workout } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
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
