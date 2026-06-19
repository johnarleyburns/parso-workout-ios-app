import SwiftUI
import SwiftData
import Charts
import CadenceCore

struct TrainingProgressView: View {
    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutModel.self) private var active
    @Environment(AppSettings.self) private var settings
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \CardioWorkout.start, order: .reverse) private var cardio: [CardioWorkout]
    @Query(sort: \Assessment.date, order: .forward) private var allAssessments: [Assessment]

    @State private var path = NavigationPath()
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

    private var assessmentSummaries: [AssessmentSummary] {
        AssessmentMath.summaries(from: allAssessments)
    }

    private func sparklineData(for summary: AssessmentSummary) -> [Assessment] {
        allAssessments.filter { $0.seriesKey == summary.id }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !assessmentSummaries.isEmpty {
                    Section("Test Trends") {
                        ForEach(assessmentSummaries) { summary in
                            Button {
                                Haptics.selection()
                                path.append(summary.kind)
                            } label: {
                                assessmentTrendRow(summary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("progress.trend.\(summary.id)")
                        }
                    }
                }

                Section {
                    if entries.isEmpty {
                        Text(showDeleted ? "No deleted workouts." : "No workouts yet — start one from Workout.")
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
                            .accessibilityIdentifier("progress.toggleDeleted")
                        }
                    }
                } footer: {
                    if showDeleted {
                        Text("Swipe to restore a deleted workout.")
                    }
                }
            }
            .navigationTitle("Progress")
            .navigationDestination(for: HistorySummaryRoute.self) { route in
                switch route {
                case .strength(let s):
                    WorkoutSummaryView(data: .from(session: s), onEdit: { path.append(s) })
                case .cardio(let c):
                    WorkoutSummaryView(data: .from(cardio: c))
                }
            }
            .navigationDestination(for: WorkoutSession.self) { SessionView(session: $0) }
            .navigationDestination(for: CardioWorkout.self) { CardioDetailView(workout: $0) }
            .navigationDestination(for: AssessmentKind.self) { AssessmentDetailView(kind: $0) }
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
        .accessibilityIdentifier("progress")
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
                    Text("\(session.orderedSets.count) sets \u{00b7} \(Format.weightValue(session.totalVolume, unit: .kilograms)) kg volume")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("progress.sessionRow")
        .swipeActions(edge: .leading) {
            if session.deletedAt != nil {
                Button { restore(session) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                    .tint(.green)
                    .accessibilityIdentifier("progress.restore")
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
                    .accessibilityIdentifier("progress.purge")
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
                    Text("\(Format.duration(c.duration))\(c.distance.map { " \u{00b7} " + Format.distance($0) } ?? "")")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("progress.cardioRow.\(c.typeValue.rawValue)")
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

    // MARK: Assessment trends

    private func assessmentTrendRow(_ summary: AssessmentSummary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: summary.kind.symbol)
                .foregroundStyle(.tint)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(AssessmentDisplay.seriesTitle(summary))
                    .font(.subheadline)
                Text(AssessmentDisplay.value(summary.latest, kind: summary.kind, unit: settings.unit))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 4)
            let data = sparklineData(for: summary)
            if data.count >= 2 {
                assessmentSparkline(data, kind: summary.kind)
                    .frame(width: 60, height: 28)
                    .accessibilityHidden(true)
            }
            if summary.count >= 2 {
                TrendBadge(trend: summary.trend)
            }
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func assessmentSparkline(_ data: [Assessment], kind: AssessmentKind) -> some View {
        Chart(data) { row in
            LineMark(
                x: .value("Date", row.date),
                y: .value("Value", sparklineValue(row.value, kind: kind))
            )
            .foregroundStyle(.tint)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }

    private func sparklineValue(_ value: Double, kind: AssessmentKind) -> Double {
        kind.unit == .weightKg ? WorkoutMath.display(value, in: settings.unit) : value
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
