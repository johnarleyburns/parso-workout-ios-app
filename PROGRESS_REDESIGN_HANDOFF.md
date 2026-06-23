# Cladiron — Progress page rebuild (handoff)

**Reference mockup: `progress_mockup.html`** (open it in a browser). The page is a
vertical stack of cards; each section below maps 1:1 to a card in that mockup,
top to bottom (§1 banner → §7 history link). Match it.

Scope: the Progress tab only — `Cadence/Cadence/Features/Progress/ProgressView.swift`
(`TrainingProgressView`), one new engine file, and one new view file. Do not touch
the Coach engine's rules, the data model, or other screens.

## Goal

Today the Progress tab is a history list (plus assessment trends) — it duplicates
Home and the History screen. Replace it with a **science-backed adaptation
dashboard**: every interpretive line is grounded in a `Citation` from your
existing `CitationRegistry` (shown via the existing `CitationLink`), and any change
under the noise threshold reads "no change," never as progress. History leaves this
tab entirely — `HistoryView` already exists and already owns the View Deleted /
restore / purge flow, so §7 is just a link to it.

## Files

- **Edit:** `Cadence/Cadence/Features/Progress/ProgressView.swift` — rewrite the body.
- **New (engine):** `CadenceCore/Sources/CadenceCore/StrengthProgress.swift` — the
  per-lift estimated-1RM time series (the engine exposes current-week snapshots but
  no longitudinal series; this adds one, pure + `swift test`-able).
- **New (view):** `Cadence/Cadence/Features/Progress/VolumeLandmarkBar.swift` —
  the reusable MEV·MAV·MRV bar.
- **Reuse unchanged:** `CitationLink`, `CitationRegistry`, `TrainingFacts`,
  `VolumeLandmarks`, `AssessmentMath`/`AssessmentSummary`, `AssessmentDetailView`,
  `HistoryView`, `Format`, `WorkoutMath`.

## One data source: a single `TrainingFacts` snapshot

Build it in the view exactly as `HomeView` builds `coachFacts`, so Home and
Progress read identical numbers:

```swift
private var facts: TrainingFacts {
    TrainingFacts.make(sessions: activeSessions,
                       assessments: allAssessments,
                       goal: settings.trainingGoal,
                       experience: settings.experienceLevel,
                       formula: settings.formula)
}
```

### Design call you asked about — `InsightEngine` vs. raw facts

Read `TrainingFacts` fields **directly** for these cards. They are descriptive
readings ("where are you"): volume, intensity, effort, frequency, strength trend —
all present whether or not they rise to a coaching flag. Keep `InsightEngine` /
`coachInsights` for Home's Coach card, which is prescriptive ("what to change
now"). That gives one source of truth for the numbers and avoids two code paths
that can disagree. If you later want a "Coach flagged this" nudge on a Progress
card, derive it by checking whether an `Insight` of matching `kind`/`part` exists
and link to Home's insights — but never recompute the number from a second path.

---

## §1 — Science banner

```swift
private var scienceBanner: some View {
    HStack(alignment: .top, spacing: 9) {
        Image(systemName: "microscope").foregroundStyle(.tint)
        Text("Every reading is tied to a study. Changes within measurement noise are shown as \u{201C}no change,\u{201D} not progress.")
            .font(.caption).foregroundStyle(.tint)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
    .accessibilityIdentifier("progress.scienceBanner")
}
```

## §2 — Strength over time (estimated 1RM)

New engine file — `CadenceCore/Sources/CadenceCore/StrengthProgress.swift`:

```swift
import Foundation

/// One lift's estimated-1RM trajectory, bucketed by ISO week — the series behind
/// the Progress "Strength over time" chart. e1RM is an *estimate* (LeSuer et al.,
/// 1997); a ±2% week-over-week band is the noise floor (matches the trend epsilon
/// in `TrainingFacts`), so small wobbles read flat. Pure + `swift test`-able.
public struct E1RMPoint: Sendable, Equatable, Identifiable {
    public let weekStart: Date
    public let e1rm: Double            // best estimated 1RM that week (kg)
    public init(weekStart: Date, e1rm: Double) { self.weekStart = weekStart; self.e1rm = e1rm }
    public var id: Date { weekStart }
}

public struct E1RMSeries: Sendable, Equatable, Identifiable {
    public let exercise: String
    public let points: [E1RMPoint]     // chronological
    public init(exercise: String, points: [E1RMPoint]) { self.exercise = exercise; self.points = points }
    public var id: String { exercise }
    public var current: Double { points.last?.e1rm ?? 0 }
    public var baseline: Double { points.first?.e1rm ?? 0 }
    public var delta: Double { current - baseline }
    /// ±2% noise floor vs the first point → rising / flat / declining.
    public var trend: TrendDirection {
        guard baseline > 0, points.count >= 2 else { return .flat }
        let r = current / baseline
        if r > 1.02 { return .rising }
        if r < 0.98 { return .declining }
        return .flat
    }
}

public enum StrengthProgress {
    /// Best estimated 1RM per ISO week for the `topN` lifts with the most working
    /// sets over `weeks`. Pass the `@Query` sessions straight in.
    public static func series(from sessions: [WorkoutSession],
                              now: Date = Date(),
                              weeks: Int = 12,
                              topN: Int = 3,
                              formula: OneRepMaxFormula = .epley,
                              calendar: Calendar = .current) -> [E1RMSeries] {
        let windowStart = calendar.date(byAdding: .day, value: -7 * weeks, to: now) ?? now
        var byLift: [String: [Date: Double]] = [:]
        var setCount: [String: Int] = [:]
        for s in sessions where s.deletedAt == nil && s.date >= windowStart && s.date <= now {
            let week = calendar.dateInterval(of: .weekOfYear, for: s.date)?.start
                ?? calendar.startOfDay(for: s.date)
            for set in s.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 && set.weight > 0 {
                guard let name = set.exercise?.name, !name.isEmpty else { continue }
                let e = WorkoutMath.estimated1RM(weight: set.weight, reps: set.reps, formula: formula)
                byLift[name, default: [:]][week] = max(byLift[name, default: [:]][week] ?? 0, e)
                setCount[name, default: 0] += 1
            }
        }
        let topLifts = setCount.sorted { $0.value > $1.value }.prefix(topN).map(\.key)
        return topLifts.compactMap { name -> E1RMSeries? in
            guard let weeks = byLift[name], !weeks.isEmpty else { return nil }
            let pts = weeks.sorted { $0.key < $1.key }.map { E1RMPoint(weekStart: $0.key, e1rm: $0.value) }
            return E1RMSeries(exercise: name, points: pts)
        }
        .sorted { $0.current > $1.current }
    }
}
```

Card (in `ProgressView`), using Swift Charts + the existing `Format`/`WorkoutMath`:

```swift
@ViewBuilder private var strengthCard: some View {
    card(title: "Strength over time", subtitle: "estimated 1RM \u{00b7} last 12 weeks",
         citation: CitationRegistry.oneRMEstimation) {
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

            VStack(spacing: 5) {
                ForEach(strengthSeries) { s in
                    HStack(spacing: 8) {
                        Text(s.exercise).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(Format.weight(s.current, unit: settings.unit, decimals: 0))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        trendTag(s.trend, delta: s.delta)
                    }
                }
            }
            .padding(.top, 8)
        }
    }
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
```

(Working-set e1RM is the *continuous* trend here; the deliberate, noise-guarded
e1RM **test** lives in §6. Both cite `oneRMEstimation`.)

## §3 — Weekly volume vs. landmarks  ← the differentiator

New view file — `Cadence/Cadence/Features/Progress/VolumeLandmarkBar.swift`:

```swift
import SwiftUI
import CadenceCore

/// One muscle's weekly working-set count placed against its MEV·MAV·MRV bands.
/// Zone color encodes `VolumeZone`; the marker is the user's set count.
struct VolumeLandmarkBar: View {
    let part: BodyPart
    let sets: Double
    let bands: VolumeBands
    let zone: VolumeZone

    private var scaleMax: Double { max(bands.mrv * 1.25, sets * 1.05, 1) }
    private func frac(_ v: Double) -> CGFloat { CGFloat(min(max(v / scaleMax, 0), 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(part.displayName).font(.caption)
                Spacer()
                Text("\(setsText) sets \u{00b7} \(zone.label)")
                    .font(.caption).foregroundStyle(zone.tint)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.orange.opacity(0.18)).frame(width: w * frac(bands.mev))
                        Rectangle().fill(Color.green.opacity(0.18)).frame(width: w * (frac(bands.mav) - frac(bands.mev)))
                        Rectangle().fill(Color.orange.opacity(0.18)).frame(width: w * (frac(bands.mrv) - frac(bands.mav)))
                        Rectangle().fill(Color.red.opacity(0.18))
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(zone.tint)
                        .frame(width: 3, height: 12)
                        .offset(x: min(w * frac(sets), w - 3))
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress.volume.\(part.rawValue)")
        .accessibilityLabel("\(part.displayName): \(setsText) sets, \(zone.label)")
    }

    private var setsText: String {
        sets == sets.rounded() ? String(Int(sets)) : String(format: "%.1f", sets)
    }
}

extension VolumeZone {
    var label: String {
        switch self {
        case .belowMEV:       "below MEV"
        case .productive:     "productive"
        case .approachingMRV: "approaching MRV"
        case .overMRV:        "over MRV"
        }
    }
    var tint: Color {
        switch self {
        case .belowMEV:       .orange
        case .productive:     .green
        case .approachingMRV: .orange
        case .overMRV:        .red
        }
    }
}
```

Card:

```swift
@ViewBuilder private var volumeCard: some View {
    let parts = BodyPart.allCases.filter { (facts.weeklySetsByPart[$0] ?? 0) > 0 }
    card(title: "Weekly volume", subtitle: "working sets per muscle vs. MEV \u{00b7} MAV \u{00b7} MRV",
         citation: CitationRegistry.volumeDoseResponse) {
        if parts.isEmpty {
            emptyNote("Once you log resistance sets, each muscle's weekly volume appears against its MEV (the minimum to grow), MAV (the productive range), and MRV (the recovery ceiling).")
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
```

## §4 — Load intensity vs. goal

```swift
@ViewBuilder private var intensityCard: some View {
    let i = facts.intensity
    card(title: "Load intensity",
         subtitle: "vs. your goal \u{2014} \(settings.trainingGoal.displayName.lowercased())",
         citation: CitationRegistry.schoenfeld2021) {
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

/// One-line read keyed to the goal's preferred band (strength→heavy,
/// hypertrophy→moderate, endurance→light). Keep it descriptive, not prescriptive.
private func intensityRead(_ i: IntensityDistribution, goal: TrainingGoal) -> String {
    switch goal {
    case .strength:
        return i.heavy >= 0.5 ? "Skewed to heavy loads \u{2014} aligned with a strength goal."
                              : "Lighter than a strength goal usually calls for."
    case .hypertrophy:
        return i.moderate >= 0.5 ? "Mostly moderate-load work \u{2014} matched to the hypertrophy rep range."
                                 : "Spread across loads \u{2014} hypertrophy favors more moderate-rep work."
    case .endurance:
        return i.light >= 0.4 ? "Plenty of higher-rep work \u{2014} aligned with an endurance goal."
                              : "Heavier than an endurance goal usually calls for."
    }
}
```

## §5 — Effort + Frequency (two compact cards, side by side)

```swift
// In body: HStack(alignment: .top, spacing: 12) { effortCard; frequencyCard }

@ViewBuilder private var effortCard: some View {
    card(title: "Effort", citation: CitationRegistry.rpeAutoregulation, compact: true) {
        if let rir = facts.avgRIR {
            Text(String(format: "%.1f", rir)).font(.title2.weight(.semibold))
            + Text(" RIR").font(.caption).foregroundStyle(.secondary)
            Text(effortRead(rir, goal: settings.trainingGoal))
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 3)
        } else {
            emptyNote("Log RPE on your sets to track how close to failure you train.")
        }
    }
}

@ViewBuilder private var frequencyCard: some View {
    let hits = BodyPart.allCases.filter { (facts.frequencyByPart[$0] ?? 0) >= 2 }
    let lows = BodyPart.allCases.filter { (facts.frequencyByPart[$0] ?? 0) == 1 }
    card(title: "Frequency", citation: CitationRegistry.frequencyMeta, compact: true) {
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
}

private func effortRead(_ rir: Double, goal: TrainingGoal) -> String {
    let target = Double(goal.targetRIR)
    if rir <= target + 0.5 && rir >= target - 0.5 { return "In the effective range for \(goal.displayName.lowercased())." }
    return rir > target ? "A little further from failure than \(goal.displayName.lowercased()) calls for."
                        : "Closer to failure than \(goal.displayName.lowercased()) usually needs."
}
```

## §6 — Test results (reuse assessments, MDC framing explicit)

Render `facts.assessments`; the trend already passes through the MDC guard in
`AssessmentSummary.trend`. Map the four cases to clear language and make `.unchanged`
explicitly read "within noise." Tapping a row pushes the existing
`AssessmentDetailView(kind:)`. Surface `facts.assessmentsDueForRetest` as a banner.

```swift
@ViewBuilder private var testResultsCard: some View {
    card(title: "Test results", citation: nil) {
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
            // One umbrella citation; each test's specific source is on its detail screen.
            CitationLink(citation: CitationRegistry.oneRMEstimation, context: "Test methods & validity")
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
```

## §7 — Full history link (and removing the inline list)

Delete from `ProgressView`: the `History`/`Deleted` `Section`, `entries`,
`strengthRow`, `cardioRow`, `showDeleted`, the delete/restore/purge confirmation
dialogs and swipe actions, and the `WorkoutSession`/`CardioWorkout`/
`HistorySummaryRoute` destinations *unless* you keep them for the pushed
`HistoryView` (see below). Replace with one link:

```swift
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
```

`HistoryView` already renders the merged list and the View Deleted / restore /
purge flow, so nothing is lost. Because `HistoryView(path:)` pushes
`HistorySummaryRoute` / `WorkoutSession` / `CardioWorkout`, register those same
destinations on Progress's `NavigationStack` (copy them verbatim from `HomeView`),
alongside the `AssessmentKind` and `ProgressRoute.history` destinations.

## Shared `card(...)` helper + view skeleton

```swift
import SwiftUI
import SwiftData
import Charts
import CadenceCore

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
        StrengthProgress.series(from: activeSessions, formula: settings.formula)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    scienceBanner
                    strengthCard
                    volumeCard
                    intensityCard
                    HStack(alignment: .top, spacing: 12) { effortCard; frequencyCard }
                    testResultsCard
                    historyLink
                }
                .padding()
            }
            .navigationTitle("Progress")
            .navigationDestination(for: AssessmentKind.self) { AssessmentDetailView(kind: $0) }
            .navigationDestination(for: ProgressRoute.self) { _ in HistoryView(path: $path) }
            // For HistoryView's rows (copied from HomeView):
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

    /// Bordered card matching progress_mockup.html; optional subtitle + citation footer.
    @ViewBuilder
    private func card<Content: View>(title: String, subtitle: String? = nil,
                                     citation: Citation? = nil, compact: Bool = false,
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
                CitationLink(citation: citation)
            }
        }
        .padding(compact ? 13 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary, lineWidth: 0.5))
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // scienceBanner / strengthCard / trendTag / volumeCard / intensityCard /
    // effortCard / frequencyCard / testResultsCard / historyLink + small helpers
    // (pct, intensityRead, effortRead, testRow, testTrendPill, pill) as defined above.
}
```

---

## Cold-start (every card degrades to an explainer, never a blank chart)

- Strength → "Log a few weeks of working sets and your estimated-1RM trend appears here…"
- Volume → explains MEV / MAV / MRV before any bar can render.
- Intensity → explains the heavy/moderate/light split.
- Effort → prompts logging RPE.
- Frequency → states the \u{2265}2\u{00d7}/week guideline.
- Tests → points to the Tests tab.

This keeps the page educational and honest on day one, and every explainer still
carries its card's citation.

## Notes / gotchas

- `microscope`, `calendar.badge.clock`, `arrow.up.right`, `arrow.down.right` are
  valid SF Symbols.
- `Format.weight(_:unit:decimals:)`, `WorkoutMath.display(_:in:)`,
  `WorkoutMath.estimated1RM(weight:reps:formula:)`, `BodyPart.allCases/.displayName/.rawValue`,
  `VolumeLandmarks.bands/zone`, `AssessmentSummary.trend/.daysSinceLatest()`,
  `AssessmentDisplay.seriesTitle/.value`, `AssessmentKind.symbol` all exist today.
- `card(... compact:)` text concatenation in `effortCard` uses `Text + Text`; keep
  both operands `Text` (no view modifiers mid-concatenation that return `some View`).
- Add `swift test` coverage for `StrengthProgress.series` (empty store → `[]`;
  one lift two weeks rising → `.rising`; within ±2% → `.flat`).

## Definition of done

- [ ] Progress is a card stack matching `progress_mockup.html` §1–§7; no inline
      history list remains (only the "View full history" link to `HistoryView`).
- [ ] Every card with an interpretation shows a tappable `CitationLink` to a real
      `CitationRegistry` entry; tapping opens `CitationDetailView`.
- [ ] Volume bars place each trained muscle against experience-scaled MEV/MAV/MRV
      with the correct zone color; `progress.volume.<part>` ids resolve.
- [ ] Test rows show "improved / declined / no change \u{00b7} within noise / baseline";
      a `.unchanged` result never reads as progress; due-for-retest banner appears.
- [ ] Strength chart plots top lifts' weekly e1RM; flat within ±2%.
- [ ] Cold-start: each card shows its explainer (with citation) when data is thin.
- [ ] `swift test` green (incl. new `StrengthProgress` tests); app builds; `progress`
      and `progress.trend.*` ids still resolve.
```
