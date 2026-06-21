# Cladiron — Home redesign + new-user onboarding (handoff)

Target: `Cadence/Cadence/Features/Home/HomeView.swift`,
`Cadence/Cadence/Features/Coach/CoachCardView.swift`,
`Cadence/Cadence/App/RootTabView.swift`, `Cadence/Cadence/App/AppSettings.swift`,
and one new file `Cadence/Cadence/Features/Onboarding/OnboardingView.swift`.

## Why

The Workout tab stacks ten sections, five of which are near-identical full-width
pills (`coachStartButton`, `startButton`, `cardioButton`, `logButton`,
`planningButton`) — no hierarchy, and the screen clips off the bottom. The Coach
card is a passive readout sitting *above* a green button that does the same job.
And there is no onboarding, so the engine never learns the user's goal /
experience / units and runs on `intermediate` / `strength` / `kilograms`.

Strategy: three calm zones. **(1)** the Coach card becomes the single hero *and*
the launch surface; **(2)** the four remaining actions collapse into one compact
quick-actions row; **(3)** "This week" + "Recent" stay but de-emphasized. Plus a
four-screen onboarding that captures goal / experience / units in ~20 s.

No engine, repository, or data-model code changes. This is presentation + one
settings flag.

---

## Part A — Declutter the Home screen (the core change)

### A1 · `CoachCardView.swift` — give the card its own Start button

Add one stored property and one button. This folds the old standalone
`coachStartButton` into the card and removes a full-width pill from Home.

```swift
struct CoachCardView: View {
    let recommendation: Recommendation
    var insightCount: Int
    var unit: MeasurementUnitPreference
    var onStart: () -> Void          // NEW
    var onSeeAll: () -> Void
    // ...
```

In `body`, immediately after `RecommendationContentView(...)` and before the
`if insightCount > 0 { ... }` block, insert:

```swift
            Button { Haptics.selection(); onStart() } label: {
                Label("Start workout", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(.green, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.coachStart")   // reuse the old id → no test churn
            .accessibilityLabel("Start the coach's workout")
```

Green is deliberate: it matches the existing "go/active" semantics already used by
the resume card and the old coach button. The card's blue tint stays as the
container; the green CTA reads as the one primary action on the screen.

### A2 · `HomeView.swift` — collapse the body stack

Replace the inner `VStack` (currently lines ~82–97) with:

```swift
                VStack(alignment: .leading, spacing: 20) {
                    if let s = active.strengthSession { resumeCard(s) }
                    CoachCardView(recommendation: coachRecommendation,
                                  insightCount: coachInsights.count,
                                  unit: settings.unit,
                                  onStart: { launchPrescription(coachRecommendation) },
                                  onSeeAll: { path.append(HomeRoute.coach) })
                    quickActionsRow
                    thisWeekCard
                    favoritesSection
                    recentWorkoutsSection
                }
                .padding()
```

`onStart` calls the exact same `launchPrescription(coachRecommendation)` the old
green button called — no behavior change, just relocation.

### A3 · `HomeView.swift` — new `quickActionsRow`

Four compact, equal-weight chips replacing `startButton` / `cardioButton` /
`logButton` / `planningButton`. Each reuses the **same a11y id and the same
action/state** as the pill it replaces, so existing sheets and UI tests keep
working.

```swift
    /// The four secondary entry points, demoted from full-width pills to one
    /// compact row (the primary action now lives inside the Coach card).
    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            quickAction("Strength", "dumbbell.fill", id: "home.startWorkout") {
                weightsStartPresented = true
            }
            quickAction("Cardio", "figure.run", id: "home.startCardio") {
                cardioPickerPresented = true
            }
            quickAction("Log", "square.and.pencil", id: "home.logWorkout") {
                logPickerPresented = true
            }
            quickAction("Programs", "books.vertical", id: "home.planning") {
                path.append(HomeRoute.planning)
            }
        }
    }

    private func quickAction(_ title: String, _ symbol: String, id: String,
                             action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.tint)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
```

### A4 · `HomeView.swift` — calm `thisWeekCard`

Replaces `thisWeekSection`, `statRow`, `coverageRow`, and `statTile`. Same four
metrics, but one quiet card instead of four loud tappable tiles. (Per-tile
tap-to-start is intentionally dropped — it was multiplying entry points. If you
want it back, re-add `onTap` to the volume/body-parts metrics.)

```swift
    /// "This week" at a glance — one calm card, not four launcher tiles.
    private var thisWeekCard: some View {
        let coverage = bodyPartsThisWeek
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                Button { Haptics.selection(); path.append(HomeRoute.coach) } label: {
                    HStack(spacing: 3) {
                        Text("Details").font(.caption)
                        Image(systemName: "chevron.right").font(.caption2)
                    }.foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                weekMetric("\(workoutsThisWeek)", "workouts", id: "home.workoutsCount")
                weekMetric("\(cardioMinutesThisWeek)", "cardio min", id: "home.cardioMinutes")
                weekMetric(Format.weight(volumeThisWeekKg, unit: settings.unit, decimals: 0),
                           "volume", id: "home.volume")
                weekMetric("\(coverage.hit.count)/\(BodyPart.allCases.count)",
                           "body parts", id: "home.bodyParts")
            }
            if !coverage.missing.isEmpty {
                Text("Missing: " + coverage.missing.map(\.displayName).joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .accessibilityIdentifier("home.bodyParts.missing")
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("home.thisWeek")
    }

    private func weekMetric(_ value: String, _ label: String, id: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.bold()).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
                .accessibilityIdentifier(id)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
```

(Note: the old "workouts this week" tile carried the **mislabeled** id
`today.steps`. Fixed above to `home.workoutsCount`. `home.cardioMinutes`,
`home.volume`, `home.bodyParts`, `home.bodyParts.missing`, and `home.thisWeek`
are preserved.)

### A5 · `HomeView.swift` — delete the now-dead members

Remove: `coachStartButton`, `startButton`, `cardioButton`, `logButton`,
`planningButton`, `thisWeekSection`, `statRow`, `coverageRow`, `statTile`. The
computed aggregates (`workoutsThisWeek`, `cardioMinutesThisWeek`,
`volumeThisWeekKg`, `bodyPartsThisWeek`) stay — `thisWeekCard` uses them. Every
`@State`, `.sheet`, and routing helper stays untouched.

---

## Part B — New-user onboarding

### B1 · `AppSettings.swift` — persist completion

In `init`, alongside the other reads:

```swift
        self.hasCompletedOnboarding = defaults.bool(forKey: "settings.hasCompletedOnboarding")
```

Inside the existing `if ProcessInfo.processInfo.arguments.contains("-uiTest")`
block, force it true so existing UI tests still land on Home:

```swift
            self.hasCompletedOnboarding = true
```

Add the property next to the others:

```swift
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "settings.hasCompletedOnboarding") }
    }
```

### B2 · `RootTabView.swift` — present onboarding once

```swift
struct RootTabView: View {
    enum Tab: Hashable { case workout, tests, progress }
    @Environment(AppSettings.self) private var settings
    @State private var selection: Tab = .workout

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }
                .tag(Tab.workout)
                .accessibilityIdentifier("tab.workout")

            TestsView()
                .tabItem { Label("Tests", systemImage: "checkmark.seal") }
                .tag(Tab.tests)
                .accessibilityIdentifier("tab.tests")

            TrainingProgressView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)
                .accessibilityIdentifier("tab.progress")
        }
        .fullScreenCover(isPresented: Binding(
            get: { !settings.hasCompletedOnboarding },
            set: { presented in if !presented { settings.hasCompletedOnboarding = true } }
        )) {
            OnboardingView()
        }
    }
}
```

(Tab labels/title kept as-is here so `P3CoachHomeUITests` stays green. The
"Today" rename is optional — see Part C.)

### B3 · New file — `Cadence/Cadence/Features/Onboarding/OnboardingView.swift`

```swift
import SwiftUI
import CadenceCore

/// First-run flow: states the privacy stance, then captures the three things the
/// Coach engine needs (goal, experience, units) so the very first Home view is
/// already personalized. Skippable; never gates on a permission.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var goal: TrainingGoal = .strength
    @State private var experience: ExperienceLevel = .intermediate
    @State private var unit: MeasurementUnitPreference = .pounds
    @State private var healthRequested = false

    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $step) {
                welcomePage.tag(0)
                goalPage.tag(1)
                experiencePage.tag(2)
                unitsPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)
            footer
        }
        .interactiveDismissDisabled()
        .onAppear {
            goal = settings.trainingGoal
            experience = settings.experienceLevel
            unit = settings.unit
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            if step > 0 {
                Button { Haptics.selection(); withAnimation { step -= 1 } } label: {
                    Image(systemName: "chevron.left").font(.headline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            Button("Skip") { Haptics.selection(); finish() }
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.skip")
        }
        .padding(.horizontal).padding(.top, 8).frame(height: 32)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button {
                Haptics.selection()
                if step < lastStep { withAnimation { step += 1 } } else { finish() }
            } label: {
                Text(step < lastStep ? "Continue" : "Start training")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(step < lastStep ? AnyShapeStyle(.tint) : AnyShapeStyle(.green),
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.primary")
            PageDots(count: lastStep + 1, index: step)
        }
        .padding(.horizontal).padding(.bottom, 12)
    }

    // MARK: Pages

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 34)).foregroundStyle(.tint)
                .frame(width: 72, height: 72)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
            Text("Private by design").font(.title.bold()).padding(.top, 22)
            Text("A strength coach built on cited sport science — that never asks you to give anything up.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 14) {
                valueRow("checkmark.circle.fill", "No ads, no account, no subscription")
                valueRow("iphone", "Your data stays on your iPhone")
                valueRow("book.closed", "Every recommendation is sourced")
            }
            .padding(.top, 28)
            Spacer(); Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func valueRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.green).frame(width: 26)
            Text(text).font(.subheadline)
            Spacer()
        }
    }

    private var goalPage: some View {
        pageScaffold(title: "What are you training for?",
                     subtitle: "This shapes your rep ranges and loads.") {
            ForEach(TrainingGoal.allCases) { g in
                selectCard(title: g.displayName, subtitle: g.summary,
                           systemImage: goalSymbol(g), selected: goal == g) { goal = g }
            }
        }
    }

    private var experiencePage: some View {
        pageScaffold(title: "How much training behind you?",
                     subtitle: "Sets your starting weekly volume.") {
            ForEach(ExperienceLevel.allCases) { e in
                selectCard(title: e.displayName, subtitle: e.summary,
                           systemImage: experienceSymbol(e), selected: experience == e) { experience = e }
            }
        }
    }

    private var unitsPage: some View {
        pageScaffold(title: "One last thing",
                     subtitle: "You can change these anytime in Settings.") {
            Text("Units").font(.subheadline.weight(.medium))
            Picker("Units", selection: $unit) {
                Text("Pounds (lb)").tag(MeasurementUnitPreference.pounds)
                Text("Kilograms (kg)").tag(MeasurementUnitPreference.kilograms)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.units")

            Button {
                Task { _ = await model.health.requestAuthorization(); healthRequested = true }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "heart.fill").font(.title2).foregroundStyle(.pink).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect Apple Health").font(.headline)
                        Text("Pull in steps & past workouts. Optional.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: healthRequested ? "checkmark.circle.fill" : "chevron.right")
                        .font(healthRequested ? .body : .caption)
                        .foregroundStyle(healthRequested ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityIdentifier("onboarding.health")
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func pageScaffold<Content: View>(title: String, subtitle: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title.bold()).padding(.top, 4)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).padding(.bottom, 10)
                content()
            }
            .padding(.horizontal, 24).padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectCard(title: String, subtitle: String, systemImage: String,
                            selected: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage).font(.title2).frame(width: 30)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.background.secondary),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.tint, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
    }

    private func goalSymbol(_ g: TrainingGoal) -> String {
        switch g {
        case .strength:    "dumbbell.fill"
        case .hypertrophy: "figure.strengthtraining.traditional"
        case .endurance:   "figure.run"
        }
    }

    private func experienceSymbol(_ e: ExperienceLevel) -> String {
        switch e {
        case .beginner:     "leaf.fill"
        case .intermediate: "flame.fill"
        case .advanced:     "trophy.fill"
        }
    }

    private func finish() {
        settings.trainingGoal = goal
        settings.experienceLevel = experience
        settings.unit = unit
        settings.hasCompletedOnboarding = true
        dismiss()
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: i == index ? 18 : 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}
```

If you use XcodeGen with folder-based sources, `xcodegen generate` will pick up
the new `Features/Onboarding/` folder automatically.

---

## Part C — Optional polish (separate commit; touches tests)

1. **Rename the tab + title to "Today"** (recommended — a coach app's home should
   answer "what do I do today?"). In `RootTabView`: case `.today`, label `"Today"`,
   `systemImage: "flame.fill"`. In `HomeView`, swap `.navigationTitle("Cladiron")`
   for an inline header showing the date + "Today" (or
   `.navigationTitle("Today")`). Keep "Cladiron" as the App Store name.
   - Test updates required: `P3CoachHomeUITests` selects `app.buttons["Workout"]`
     → change to `["Today"]`. Any test asserting nav title `"Cladiron"` → `"Today"`.

2. **Section spacing** — the body now has 4–5 zones; `spacing: 20` (set in A2)
   reads better than the old 18 with fewer, heavier blocks.

---

## Test impact summary

Preserved (no change): `coach.card`, `coach.card.action`, `coach.card.target`,
`coach.card.why`, `coach.card.citation`, `home.coachStart`, `home.startWorkout`,
`home.startCardio`, `home.logWorkout`, `home.planning`, `home.thisWeek`,
`home.cardioMinutes`, `home.volume`, `home.bodyParts`, `home.bodyParts.missing`,
`tab.workout` / `tab.tests` / `tab.progress`.

Changed: `today.steps` → `home.workoutsCount` (was mislabeled). Dropped: the
cardio progress-bar id and per-tile launcher tap targets on the stats.

New: `home.coachStart` now lives inside the Coach card; `onboarding.*` ids.

Part C only: tab label `"Workout"` → `"Today"` breaks `["Workout"]` lookups.

---

## Execution checklist

- [ ] A1: `onStart` param + green Start button in `CoachCardView`.
- [ ] A2: replace `HomeView` body `VStack`.
- [ ] A3: add `quickActionsRow` + `quickAction(_:_:id:action:)`.
- [ ] A4: add `thisWeekCard` + `weekMetric(_:_:id:)`.
- [ ] A5: delete the five pills + `thisWeekSection`/`statRow`/`coverageRow`/`statTile`.
- [ ] B1: `hasCompletedOnboarding` in `AppSettings` (+ force true under `-uiTest`).
- [ ] B2: onboarding `fullScreenCover` in `RootTabView`.
- [ ] B3: new `OnboardingView.swift`.
- [ ] `swift test` in `CadenceCore` (should be untouched/green), then build + run
      UI tests; reset the simulator or clear the `hasCompletedOnboarding` default
      to see the flow again.
- [ ] (Optional, Part C) Today rename + the two test edits.
```