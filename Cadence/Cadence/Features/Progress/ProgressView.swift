import SwiftUI
import SwiftData
import Charts
import CadenceCore
import CadenceFeatures

enum ProgressRoute: Hashable { case history }

struct TrainingProgressView: View {
    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutModel.self) private var active
    @Environment(AppSettings.self) private var settings
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Assessment.date, order: .forward) private var allAssessments: [Assessment]

    @State private var path = NavigationPath()

    private var activeSessions: [WorkoutSession] { sessions.filter { $0.deletedAt == nil } }
    private var facts: TrainingFacts {
        TrainingFacts.make(sessions: activeSessions, assessments: allAssessments,
                           goal: settings.trainingGoal, experience: settings.experienceLevel,
                           formula: settings.formula)
    }
    private var strengthSeries: [E1RMSeries] {
        ProgressPresenter.strengthSeries(sessions: activeSessions, formula: settings.formula)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    scienceBanner
                    strengthCard
                    PRTimelineView(sessions: activeSessions)
                    ConsistencyHeatmapView(sessions: activeSessions)
                    volumeCard
                    intensityCard
                    HStack(alignment: .top, spacing: 12) { effortCard; frequencyCard }
                    testResultsCard
                    historyLink
                }
                .padding()
            }
            .background { CadenceGlassBackdrop(tint: .blue) }
            .navigationTitle("Progress")
            .navigationDestination(for: AssessmentKind.self) { AssessmentDetailView(kind: $0) }
            .navigationDestination(for: ProgressRoute.self) { _ in HistoryView(path: $path) }
            .navigationDestination(for: HistorySummaryRoute.self) { route in
                switch route {
                case .strength(let s): WorkoutSummaryView(data: .from(session: s), onEdit: { path.append(s) })
                case .cardio(let c):   CardioDetailView(workout: c)
                }
            }
            .navigationDestination(for: WorkoutSession.self) { SessionView(session: $0) }
            .navigationDestination(for: CardioWorkout.self) { CardioDetailView(workout: $0) }
        }
        .accessibilityIdentifier("progress")
    }

    // MARK: - Card helper

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
        .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: tint)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - §1 Science banner

    private var scienceBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "flask").foregroundStyle(.tint)
            Text("Every reading is tied to a study. Changes within measurement noise are shown as \u{201C}no change,\u{201D} not progress.")
                .font(.caption).foregroundStyle(.tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 13, style: .continuous), tint: .blue)
        .accessibilityIdentifier("progress.scienceBanner")
    }

    // MARK: - §2 Strength over time

    @ViewBuilder private var strengthCard: some View {
        card(title: "Strength over time", subtitle: "estimated 1RM \u{00b7} last 12 weeks",
             citation: CitationRegistry.oneRMEstimation, tint: .blue) {
            if strengthSeries.allSatisfy({ $0.points.count < 2 }) {
                emptyNote("Log a few weeks of working sets and your estimated-1RM trend appears here. e1RM is projected from the weight and reps of your heaviest sets.")
            } else {
                Chart {
                    ForEach(strengthSeries) { s in
                        ForEach(s.points) { p in
                            LineMark(x: .value("Week", p.weekStart),
                                     y: .value("e1RM", WorkoutMath.display(p.e1rm, in: settings.unit)))
                            .foregroundStyle(by: .value("Lift", s.exercise))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 150)
                .accessibilityElement()
                .accessibilityLabel("Estimated 1RM trend, last 12 weeks")
                .accessibilityValue(strengthTrendSummary)

                VStack(spacing: 5) {
                    ForEach(strengthSeries) { s in
                        HStack(spacing: 8) {
                            Text(s.exercise).font(.subheadline).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer()
                            Text(Format.weight(s.current, unit: settings.unit, decimals: 0))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                            trendTag(s.trend, delta: s.delta)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(s.exercise): \(Format.weight(s.current, unit: settings.unit, decimals: 0)), \(trendLabel(s.trend, delta: s.delta))")
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    /// One-line VoiceOver summary of the (visually hidden) e1RM chart.
    private var strengthTrendSummary: String {
        ProgressPresenter.strengthTrendSummary(series: strengthSeries, unit: settings.unit)
    }

    private func trendLabel(_ t: TrendDirection, delta: Double) -> String {
        ProgressPresenter.trendLabel(t, delta: delta, unit: settings.unit)
    }

    @ViewBuilder private func trendTag(_ t: TrendDirection, delta: Double) -> some View {
        switch t {
        case .rising:
            Label("+" + Format.weight(abs(delta), unit: settings.unit, decimals: 0), systemImage: "arrow.up.right")
                .font(.caption).foregroundStyle(.green)
        case .declining:
            Label("\u{2212}" + Format.weight(abs(delta), unit: settings.unit, decimals: 0), systemImage: "arrow.down.right")
                .font(.caption).foregroundStyle(.orange)
        case .flat:
            Label("flat", systemImage: "minus").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - §3 Weekly volume

    @ViewBuilder private var volumeCard: some View {
        let parts = BodyPart.allCases.filter { (facts.weeklySetsByPart[$0] ?? 0) > 0 }
        card(title: "Weekly volume", subtitle: "working sets per muscle vs. experience-scaled ranges",
             citation: CitationRegistry.volumeDoseResponse, tint: .teal) {
            if parts.isEmpty {
                emptyNote("Once you log resistance sets, each muscle's weekly volume appears against an evidence-informed starting range and high-end range for your experience level.")
            } else {
                VStack(spacing: 10) {
                    ForEach(parts, id: \.self) { part in
                        VolumeLandmarkBar(
                            part: part,
                            sets: facts.weeklySetsByPart[part] ?? 0,
                            bands: VolumeLandmarks.bands(for: part, experience: settings.experienceLevel),
                            zone: VolumeLandmarks.zone(sets: facts.weeklySetsByPart[part] ?? 0,
                                                       for: part, experience: settings.experienceLevel))
                    }
                }
                Text("Bands scale with your experience level.")
                    .font(.caption2).foregroundStyle(.tertiary).padding(.top, 8)
            }
        }
    }

    // MARK: - §4 Load intensity

    @ViewBuilder private var intensityCard: some View {
        let i = facts.intensity
        card(title: "Load intensity",
             subtitle: "vs. your goal \u{2014} \(settings.trainingGoal.displayName.lowercased())",
             citation: CitationRegistry.schoenfeld2021, tint: .blue) {
            if i.sampleCount == 0 {
                emptyNote("Log the weight on your sets and we'll show how your work splits across heavy, moderate, and light loads \u{2014} and whether that matches your goal's rep range.")
            } else {
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
            if let rir = facts.avgRIR {
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

    @ViewBuilder private var frequencyCard: some View {
        let hits = BodyPart.allCases.filter { (facts.frequencyByPart[$0] ?? 0) >= 2 }
        let lows = BodyPart.allCases.filter { (facts.frequencyByPart[$0] ?? 0) == 1 }
        card(title: "Frequency", citation: CitationRegistry.frequencyMeta, compact: true, tint: .orange, equalHeight: true) {
            if facts.frequencyByPart.isEmpty {
                emptyNote("Train each muscle \u{2265}2\u{00d7}/week to get more from the same weekly sets.")
            } else {
                if !hits.isEmpty {
                    Text(hits.map(\.displayName).joined(separator: " \u{00b7} ") + " 2\u{00d7}/wk")
                        .font(.caption).foregroundStyle(.green)
                }
                if !lows.isEmpty {
                    Text(lows.map(\.displayName).joined(separator: " \u{00b7} ") + " 1\u{00d7}/wk")
                        .font(.caption).foregroundStyle(.orange).padding(.top, 2)
                }
            }
        }
        .accessibilityIdentifier("progress.frequencyCard")
    }

    private func effortRead(_ rir: Double, goal: TrainingGoal) -> String {
        ProgressPresenter.effortRead(rir, goal: goal)
    }

    // MARK: - §6 Test results

    @ViewBuilder private var testResultsCard: some View {
        card(title: "Test results", citation: nil, tint: .blue) {
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

    // MARK: - §7 Full history link

    private var historyLink: some View {
        Button { Haptics.selection(); path.append(ProgressRoute.history) } label: {
            HStack {
                Text("View full history")
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(.tint).padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("progress.fullHistory")
    }
}
