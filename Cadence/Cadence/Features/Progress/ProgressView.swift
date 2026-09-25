import SwiftUI
import SwiftData
import Charts
import CadenceCore
import CadenceFeatures

private struct ProgressSessionSignature: Equatable {
    let id: UUID
    let date: Date
    let updatedAt: Date
    let deletedAt: Date?
}

private struct ProgressPreparedSnapshot: Sendable {
    let strength: StrengthProgressChartData
    let prEvents: [PREvent]
}

struct TrainingProgressView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \CardioWorkout.start, order: .reverse) private var cardio: [CardioWorkout]
    @Query(sort: \Assessment.date, order: .forward) private var allAssessments: [Assessment]

    @State private var path = NavigationPath()
    @State private var questionSelection = ProgressQuestionSelection.persisted()
    @State private var preparedStrengthData: StrengthProgressChartData?
    @State private var preparedPREvents: [PREvent] = []
    @State private var preparedFacts: TrainingFacts?
    @State private var selectedStrengthNames = ProgressStrengthSelection.persisted().selectedNames

    private var activeSessions: [WorkoutSession] { sessions.filter { $0.deletedAt == nil } }
    private var facts: TrainingFacts? { preparedFacts }

    private var progressSignature: [ProgressSessionSignature] {
        sessions.map { ProgressSessionSignature(id: $0.id, date: $0.date,
                                                 updatedAt: $0.updatedAt,
                                                 deletedAt: $0.deletedAt) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if questionSelection.selected == .workoutHistory {
                    HistoryView(path: $path)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ProgressQuestionSummaryView(
                                selection: $questionSelection,
                                sessions: activeSessions,
                                detailContent: { question in
                                    progressQuestionContent(for: question)
                                })
                        }
                        .padding()
                        // RootTabView reserves the glass dock's measured safe
                        // area. This explicit content tail keeps the last
                        // Progress card scrollable above that dock even when
                        // the nested NavigationStack does not propagate the
                        // inset into its ScrollView content.
                        .padding(.bottom, CadenceTabBarClearance.scrollContentBottom)
                    }
                }
            }
            .background { CadenceGlassBackdrop(tint: .blue) }
            .navigationTitle("Progress")
            .navigationDestination(for: AssessmentKind.self) { AssessmentDetailView(kind: $0) }
            .navigationDestination(for: HistorySummaryRoute.self) { route in
                switch route {
                case .strength(let id):
                    if let session = sessions.first(where: { $0.id == id }) {
                        WorkoutSummaryView(data: .from(session: session),
                                           onEdit: { path.append(HistorySummaryRoute.strengthFocused(id, nil)) })
                    } else {
                        MissingWorkoutRouteView()
                    }
                case .strengthFocused(let id, let exerciseID):
                    if let session = sessions.first(where: { $0.id == id }) {
                        SessionView(session: session, initiallyExpandedExerciseID: exerciseID)
                    } else {
                        MissingWorkoutRouteView()
                    }
                case .cardio(let id):
                    if let workout = cardio.first(where: { $0.id == id }) {
                        CardioDetailView(workout: workout)
                    } else {
                        MissingWorkoutRouteView()
                    }
                }
            }
        }
        .task(id: progressSignature) {
            await prepareProgressData()
        }
        .onChange(of: questionSelection) { _, selection in
            selection.persist()
        }
        .onChange(of: selectedStrengthNames) { _, names in
            ProgressStrengthSelection(selectedNames: names).persist()
        }
        .accessibilityIdentifier("progress")
    }

    private func prepareProgressData() async {
        let inputs = activeSessions.map { session in
            StrengthProgressSessionInput(
                date: session.date,
                deleted: session.deletedAt != nil,
                sets: session.orderedSets.compactMap { set in
                    guard let name = set.exercise?.name, !name.isEmpty else { return nil }
                    return StrengthProgressSetInput(exerciseName: name,
                                                    completedAt: set.completedAt,
                                                    weightKg: set.effectiveLoadKg,
                                                    reps: set.reps,
                                                    isWarmup: set.isWarmup,
                                                    isOwnerSet: set.isOwnerSet)
                })
        }
        let prSamples = inputs.flatMap { session in
            session.sets.filter { $0.isOwnerSet }.map {
                ExerciseSetSample(exerciseName: $0.exerciseName,
                                  sample: SetSample(weight: $0.weightKg,
                                                    reps: $0.reps,
                                                    date: $0.completedAt,
                                                    isWarmup: $0.isWarmup))
            }
        }
        let formula = settings.formula
        let rule = settings.prRule
        let prepared = await Task.detached(priority: .userInitiated) {
            ProgressPreparedSnapshot(
                strength: StrengthProgress.chartData(from: inputs, formula: formula),
                prEvents: PRTimeline.events(sets: prSamples, rule: rule, formula: formula))
        }.value
        guard !Task.isCancelled else { return }
        preparedStrengthData = prepared.strength
        preparedPREvents = prepared.prEvents
        // The slower insight facts are prepared once per history snapshot. The
        // chart and PR tabs never depend on this work, so they remain responsive
        // even while the secondary reports are being refreshed.
        await Task.yield()
        preparedFacts = TrainingFacts.make(sessions: activeSessions,
                                           assessments: allAssessments,
                                           goal: settings.trainingGoal,
                                           experience: settings.experienceLevel,
                                           formula: formula)
    }
    @ViewBuilder
    private func progressQuestionContent(for question: ProgressQuestion) -> some View {
        switch question {
        case .strengthOverTime:
            strengthCard
        case .tests:
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink { TestsView() } label: {
                    Label("Perform a Test…", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("progress.performTest")
                testResultsCard
            }
        case .personalRecords:
            PRTimelineView(events: preparedPREvents)
        case .intensity:
            intensityCard
        case .effort:
            effortCard
        case .consistency:
            EmptyView()
        case .workoutHistory:
            EmptyView()
        }
    }

    @ViewBuilder
    private func card<Content: View>(title: String, subtitle: String? = nil,
                                     citation: Citation? = nil, compact: Bool = false,
                                     tint: Color? = nil, equalHeight: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(compact ? .subheadline.weight(.semibold) : .headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
            } else {
                Color.clear.frame(height: compact ? 6 : 10)
            }
            content()
            if let citation {
                Divider().padding(.top, 12).padding(.bottom, 8)
                CitationLink(citation: citation, compact: true)
            }
        }
        .padding(compact ? 13 : 16)
        // `equalHeight` fills the row so side-by-side cards match the taller one
        // (issue 12 — Frequency was shorter than Effort).
        .frame(maxWidth: .infinity, maxHeight: equalHeight ? .infinity : nil, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: tint)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Strength over time

    @ViewBuilder private var strengthCard: some View {
        card(title: "Strength over time", subtitle: "estimated 1RM \u{00b7} last 12 weeks",
             citation: CitationRegistry.oneRMEstimation, tint: .blue) {
            if let preparedStrengthData {
                ProgressStrengthChartView(data: preparedStrengthData,
                                          unit: settings.unit,
                                          selectedNames: $selectedStrengthNames)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .accessibilityLabel("Preparing strength chart")
            }
        }
    }

    // MARK: - §4 Load intensity

    @ViewBuilder private var intensityCard: some View {
        card(title: "Load intensity",
             subtitle: "vs. your goal \u{2014} \(settings.trainingGoal.displayName.lowercased())",
             citation: CitationRegistry.schoenfeld2021, tint: .blue) {
            if let i = facts?.intensity, i.sampleCount > 0 {
                GeometryReader { geo in
                    let w = geo.size.width
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.blue.opacity(0.25)).frame(width: w * CGFloat(i.heavy))
                        Rectangle().fill(Color.green.opacity(0.25)).frame(width: w * CGFloat(i.moderate))
                        Rectangle().fill(Color.gray.opacity(0.20)).frame(width: w * CGFloat(i.light))
                    }
                }
                .frame(height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
                HStack {
                    Text("heavy \(pct(i.heavy))").foregroundStyle(.blue)
                    Spacer(); Text("moderate \(pct(i.moderate))").foregroundStyle(.green)
                    Spacer(); Text("light \(pct(i.light))").foregroundStyle(.secondary)
                }
                .font(.caption2).padding(.top, 5)
                Text(intensityRead(i, goal: settings.trainingGoal))
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            } else {
                emptyNote("Log the weight on your sets and we'll show how your work splits across heavy, moderate, and light loads \u{2014} and whether that matches your goal's rep range.")
            }
        }
    }

    private func pct(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }

    private func intensityRead(_ i: IntensityDistribution, goal: TrainingGoal) -> String {
        ProgressPresenter.intensityRead(i, goal: goal)
    }

    // MARK: - §5 Effort + Frequency

    @ViewBuilder private var effortCard: some View {
        card(title: "Effort", citation: CitationRegistry.rpeAutoregulation, compact: true, tint: .orange, equalHeight: true) {
            if let rir = facts?.avgRIR {
                Text(String(format: "%.1f", rir)).font(.title2.weight(.semibold))
                + Text(" RIR").font(.caption).foregroundStyle(.secondary)
                Text(effortRead(rir, goal: settings.trainingGoal))
                    .font(.caption2).foregroundStyle(.secondary).padding(.top, 3)
            } else {
                emptyNote("Log RPE on your sets to track how close to failure you train.")
            }
        }
        .accessibilityIdentifier("progress.effortCard")
    }

    private func effortRead(_ rir: Double, goal: TrainingGoal) -> String {
        ProgressPresenter.effortRead(rir, goal: goal)
    }

    // MARK: - §6 Test results

    @ViewBuilder private var testResultsCard: some View {
        card(title: "Test results", citation: nil, tint: .blue) {
            if let facts {
                if facts.assessments.isEmpty {
                    emptyNote("Run a test from the Tests tab \u{2014} strength, push-ups, plank, or a VO\u{2082}max field test \u{2014} and your results trend here, noise-guarded.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(facts.assessments.enumerated()), id: \.element.id) { idx, s in
                            if idx > 0 { Divider() }
                            Button { Haptics.selection(); path.append(s.kind) } label: { testRow(s) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("progress.trend.\(s.id)")
                        }
                    }
                    ForEach(facts.assessmentsDueForRetest) { s in
                        HStack(spacing: 7) {
                            Image(systemName: "calendar.badge.clock").foregroundStyle(.orange)
                            Text("\(AssessmentDisplay.seriesTitle(s)) is due to re-test (\(s.daysSinceLatest() / 7) weeks).")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 8)
                    }
                    Divider().padding(.top, 12).padding(.bottom, 8)
                    CitationLink(citation: CitationRegistry.oneRMEstimation, context: "Test methods & validity", compact: true)
                }
            } else {
                ProgressView("Preparing test results")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func testRow(_ s: AssessmentSummary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: s.kind.symbol).foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(AssessmentDisplay.seriesTitle(s)).font(.subheadline)
                Text(AssessmentDisplay.value(s.latest, kind: s.kind, unit: settings.unit))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            testTrendPill(s.trend)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6).contentShape(Rectangle())
    }

    @ViewBuilder private func testTrendPill(_ t: AssessmentTrend) -> some View {
        switch t {
        case .improved:
            pill("improved", .green, bg: .green.opacity(0.15))
        case .declined:
            pill("declined", .red, bg: .red.opacity(0.15))
        case .unchanged:
            pill("no change \u{00b7} within noise", .secondary, bg: .gray.opacity(0.15))
        case .single:
            Text("baseline").font(.caption2).foregroundStyle(.tertiary)
        }
    }
    private func pill(_ t: String, _ fg: Color, bg: Color) -> some View {
        Text(t).font(.caption2).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(bg, in: Capsule())
    }

}
