import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// Home dashboard (field-test round 3): a simple step count + workouts-this-week,
/// the Start Workout hero, and trends / cardio history / workout history surfaced
/// directly — not hidden under menus. A get-ready countdown runs before a workout.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(ActiveWorkoutModel.self) private var active
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \CardioWorkout.start, order: .reverse) private var cardio: [CardioWorkout]

    @State private var typePickerPresented = false
    @State private var path = NavigationPath()
    @State private var cardioType: CardioType?
    @State private var outdoorType: CardioType?
    @State private var intervalType: WorkoutType?
    @State private var intervalLaunch: IntervalLaunch?
    @State private var pending: PendingWorkout?
    @State private var today: DayActivity?
    @State private var trend: [DayActivity] = []

    private var weekCount: Int {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        return sessions.filter { $0.date >= weekAgo }.count + cardio.filter { $0.start >= weekAgo }.count
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let s = active.strengthSession { resumeCard(s) }
                    statRow
                    startButton
                    trendSection
                    cardioSection
                    historySection
                }
                .padding()
            }
            .navigationTitle("Cadence")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(HomeRoute.settings) } label: { Image(systemName: "gearshape") }
                        .accessibilityIdentifier("home.settings").accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: WorkoutSession.self) { SessionView(session: $0) }
            .navigationDestination(for: CardioWorkout.self) { CardioDetailView(workout: $0) }
            .navigationDestination(for: HistorySummaryRoute.self) { route in
                // A5 — history rows open the read-only summary; strength offers Edit
                // (pushes the live session into the set editor).
                switch route {
                case .strength(let s):
                    WorkoutSummaryView(data: .from(session: s), onEdit: { path.append(s) })
                case .cardio(let c):
                    WorkoutSummaryView(data: .from(cardio: c))
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .stats: TrendsView()
                case .history: HistoryView(path: $path)
                case .cardio: CardioView()
                case .settings: SettingsView()
                }
            }
            .task { today = await model.health.todayActivity(); trend = await model.health.activityTrend(days: 7) }
            .refreshable { today = await model.health.todayActivity(); trend = await model.health.activityTrend(days: 7) }
            .sheet(isPresented: $typePickerPresented) {
                WorkoutTypePicker { type in typePickerPresented = false; start(type) }
            }
            .sheet(item: $cardioType) { RecordCardioView(initialType: $0) }
            .fullScreenCover(item: $outdoorType) { OutdoorCardioView(type: $0) }
            .sheet(item: $intervalType) { wType in
                IntervalSetupView(type: wType) { plan in
                    intervalType = nil
                    begin(.interval(IntervalLaunch(plan: plan, saveType: wType.cardioType ?? .hiit)))
                }
            }
            .fullScreenCover(item: $intervalLaunch) { IntervalView(plan: $0.plan, saveType: $0.saveType) }
            .fullScreenCover(item: $pending) { p in
                PreWorkoutCountdownView(seconds: settings.preWorkoutCountdown,
                                        onStart: { let k = p.kind; pending = nil; launch(k) },
                                        onCancel: { pending = nil })
            }
        }
    }

    // MARK: Top stats

    private var statRow: some View {
        HStack(spacing: 14) {
            statTile("\(Format.integer(today?.steps ?? 0))", "steps today", id: "today.steps")
            statTile("\(weekCount)", "workouts this week", id: "home.weekCount")
        }
    }
    private func statTile(_ value: String, _ label: String, id: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title.bold()).monospacedDigit().accessibilityIdentifier(id)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var startButton: some View {
        Button { typePickerPresented = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill").font(.largeTitle)
                Text("Start Workout").font(.title2.bold())
                Spacer()
                Image(systemName: "chevron.right").font(.headline).opacity(0.8)
            }
            .padding(.vertical, 22).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 84)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.startWorkout").accessibilityLabel("Start a workout")
    }

    // MARK: Inline sections (surfaced, not hidden)

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Trends", route: .stats, id: "home.stats")
            Chart(trend) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.steps))
                    .foregroundStyle(.green.gradient)
                RuleMark(y: .value("Goal", settings.stepGoal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .frame(height: 120)
            .accessibilityIdentifier("today.trendChart")
        }
    }

    private var cardioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Recent cardio", route: .cardio, id: "home.cardio")
            if cardio.isEmpty {
                Text("No cardio yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(cardio.prefix(3)) { w in
                Button { path.append(HistorySummaryRoute.cardio(w)) } label: {
                    HStack {
                        Image(systemName: w.typeValue.symbol).foregroundStyle(.tint).frame(width: 26)
                        Text(w.typeValue.displayName)
                        Spacer()
                        Text(w.start.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.cardioRow.\(w.typeValue.rawValue)")
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Recent workouts", route: .history, id: "home.train")
            if sessions.isEmpty {
                Text("No workouts yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(sessions.prefix(3)) { s in
                Button { path.append(HistorySummaryRoute.strength(s)) } label: {
                        HStack {
                            Image(systemName: "dumbbell").foregroundStyle(.tint).frame(width: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.title.isEmpty ? "Workout" : s.title)
                                Text("\(s.orderedSets.count) sets").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(s.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.sessionRow")
                }
            }
    }

    private func sectionHeader(_ title: String, route: HomeRoute, id: String) -> some View {
        Button { path.append(route) } label: {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("See all").font(.caption)
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func resumeCard(_ session: WorkoutSession) -> some View {
        Button { path.append(session) } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume \(session.title.isEmpty ? "Workout" : session.title)").font(.headline)
                    Text("\(session.orderedSets.count) sets logged").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("home.resume")
    }

    // MARK: Routing (countdown gate)

    private func start(_ type: WorkoutType) {
        if type.isStrength { begin(.strength) }
        else if type.usesGPS, let c = type.cardioType { begin(.outdoor(c)) }
        else if type == .hiit || type == .boxing { intervalType = type }
        else if let c = type.cardioType { begin(.timer(c)) }
    }
    private func begin(_ kind: PendingWorkout.Kind) {
        if settings.preWorkoutCountdown <= 0 { launch(kind) } else { pending = PendingWorkout(kind: kind) }
    }
    private func launch(_ kind: PendingWorkout.Kind) {
        switch kind {
        case .strength:
            if let s = try? WorkoutRepository.createSession(title: "Workout", in: context) {
                active.startStrength(s); path.append(s)
            }
        case .outdoor(let c): outdoorType = c
        case .interval(let l): intervalLaunch = l
        case .timer(let c): cardioType = c
        }
    }
}

/// What to launch once the countdown finishes.
struct PendingWorkout: Identifiable {
    let id = UUID()
    enum Kind { case strength, outdoor(CardioType), interval(IntervalLaunch), timer(CardioType) }
    let kind: Kind
}

/// Pushed destinations reachable from Home.
enum HomeRoute: Hashable { case stats, history, cardio, settings }

/// A history row's read-only summary destination (field-testing Round 4 A5).
/// Wraps the `@Model` row (already `Hashable`) so the big `WorkoutSummaryData`
/// value type needn't be `Hashable`.
enum HistorySummaryRoute: Hashable {
    case strength(WorkoutSession)
    case cardio(CardioWorkout)
}
