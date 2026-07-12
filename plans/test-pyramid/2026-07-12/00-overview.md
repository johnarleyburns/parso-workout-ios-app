# Test pyramid rebuild: 148 simulator tests → ~10 smoke + ~300 headless unit tests

**Date:** 2026-07-12
**Status:** planned, not started
**Branch plan:** one branch + PR per phase (see rollout table at the end)

---

## 1. Problem

The simulator test suite is unusable. 148 XCUITest functions each cold-launch the app, with a
**25-second default `waitForExistence`**, a **3× retry-on-failure** policy in
`Cadence/Cadence.xctestplan`, hand-rolled tap-retry loops in `UITestHelpers.swift`, and
`Thread.sleep` calls that assert on real wall-clock timers. A full run takes 25–45 minutes,
saturates the laptop, and is flaky enough that CI never runs it —
`.github/workflows/ios.yml` only runs `swift test` on CadenceCore, then archives.

## 2. What the code does today

`CadenceCore` is healthy: **791** headless XCTest functions, `swift test`, no simulator, and
**32 of its 70 test files already drive a real in-memory SwiftData store** via
`CadenceStore.makeModelContainer(inMemory: true)`.

The app target is not. **~15k LOC of logic sits inside SwiftUI `View` structs**, where nothing
but XCUITest can reach it:

| File | LOC | Logic trapped inside |
|---|---|---|
| `Cadence/Cadence/Features/Train/SessionView.swift` | **1,778** | `prescription(for:)` :123, `effectiveLadder(for:)` :149, `plannedSetCount(for:)` :154, `plannedReps(for:setIndex:performerID:)` :161, `lastSessionWeight(for:performerID:)` :247, `recordInlineSet(for:)` :260, `roster` :86, `attributablePartners` :91, `isBodyweight(_:)` :104, `plannedOnlyNames` :108 |
| `Cadence/Cadence/Features/Home/HomeView.swift` | **1,135** | `HomeCoachSnapshot` :66, **`CoachSignature` :128**, `coachSignature` :140, `buildCoachSnapshot()` :159, `computeTestRecommendation()` :113, `coachSurfaceState` :180, `handleAddOn` :1008, `launchDecision` :1021 |
| `Cadence/Cadence/Features/Home/WorkoutPlanEditor.swift` | 500 | `EditablePlan.from(session:)` / `.from(plan:ladder:unit:)` / `.from(recommendation:)` / `.from(coach:)`, `normalizedPartnerIDs`, `explicitPartnerIDs` |
| `Cadence/Cadence/Features/Coach/YourWeekView.swift` | 455 | `weeklyZoneMinutes(since:)`, `zoneRows`, `modality(for:)`, `intensity(for:)` — coach-domain logic in a view |
| `Cadence/Cadence/Features/Progress/ProgressView.swift` | 369 | `strengthSeries`, `strengthTrendSummary`, `intensityRead(_:goal:)`, `effortRead(_:goal:)` |
| `Cadence/Cadence/Shared/Formatting.swift` | 131 | 12 pure functions, **zero tests** — it even `import SwiftUI`s without using it |
| `Cadence/Cadence/Store/StoreService.swift` | 195 | Entitlement + trial resolution, **untested** |

> **`CoachSignature` is the sharpest example.** It is the equatable key that decides when the
> entire coach pipeline re-runs — a correctness-critical cache-invalidation rule. It has **no
> test**. The only thing guarding it is `HomeRefreshUITests`, a single flaky simulator test.

So XCUITest is being used as a unit-test harness for pure functions. That is the whole problem.
No amount of `xcodebuild` flag tuning fixes it.

## 3. Design

Add a third SwiftPM target. Logic moves to where `swift test` can reach it headlessly; views
become thin renderers of prepared state; the XCUITest suite shrinks to what genuinely needs an OS.

```
CadenceCore/                          ← ONE package, THREE library targets
  Sources/
    CadenceCore/                      (unchanged — 791 tests, domain logic)
    CadenceFeatures/                  ★ NEW — everything currently trapped in Views
      Format.swift                      (from Cadence/Shared/Formatting.swift)
      SessionViewModel.swift            (from SessionView.swift)
      HomeCoachModel.swift              (from HomeView.swift — incl. CoachSignature)
      EditablePlan.swift                (from WorkoutPlanEditor.swift)
      HistoryPresenter.swift
      YourWeekPresenter.swift
      ProgressPresenter.swift
      AssessmentDisplay.swift
      ExportPresenter.swift
      CoachRouter.swift                 ★ NEW — pure navigation decisions
      OnboardingModel.swift             ★ NEW — extracted state machine
      ActiveWorkoutModel.swift          (moved)
      IntervalRunner.swift              (moved, brings its 17 tests)
      RestTimerModel.swift              (moved, brings its 6 tests)
      CardioRecorder.swift              (moved)
      IntervalCueScheduler.swift        (moved)
      SettingsStore.swift               (AppSettings logic, UserDefaults-injectable)
      EntitlementResolver.swift         (StoreService logic, StoreKit-free)
      Clock.swift                       ★ NEW — `now: () -> Date` seam
    CadenceFixtures/                  ★ NEW — shared seed catalog
      Fixtures.swift                    (from Cadence/App/UITestSeed.swift)
      FakeHealthProvider.swift          (from Cadence/Services/FakeProviders.swift)
  Tests/
    CadenceCoreTests/                 (unchanged)
    CadenceFeaturesTests/             ★ NEW — the bulk of the new coverage

Cadence/Cadence/Features/…            ← thin SwiftUI: takes state, renders it
Cadence/CadenceUITests/               ← 37 files / 148 tests → ~10 smoke tests
```

### Hard constraint

`CadenceFeatures` imports **Foundation + SwiftData + Observation only — no SwiftUI, no
HealthKit, no StoreKit, no UIKit.** That is what keeps it buildable and testable on macOS under
`swift test`. Where a view currently gets a `Color` or `Image` from logic (e.g.
`AssessmentDisplay`'s trend tint/symbol), the extracted function returns a **semantic enum**
(`TrendDirection.improving`) and the view maps it to a `Color`. That is the correct design anyway.
Enforce with a CI grep.

### Why this is cheaper than it sounds

- **The platform boundaries are already protocols.** `CadenceCore/Sources/CadenceCore/Services.swift`
  declares `HealthDataProviding` (:199), `HeartRateMonitoring` (:236), `LocationTracking` (:264).
  View models depend on those, not on HealthKit/CoreBluetooth. Only the thin concrete adapters
  (`Services/HealthKitProvider.swift`, `HeartRateMonitor.swift`, `LocationTracker.swift`,
  `Store/StoreService.swift`) stay in the app target.
- **Headless SwiftData is already proven** — 32 core test files do it today, and the package
  already declares `.macOS(.v14)`.
- **The fixture catalog already exists.** `Cadence/Cadence/App/UITestSeed.swift` (342 LOC) has 15
  seed builders (`priorBench`, `historyMixed`, `coachWednesdayComplete`, `coachAerobicGap`, …)
  that construct realistic SwiftData graphs. They are the most valuable asset in the UI suite and
  they are trapped in the app target.

### The core pattern

Keep `@Query` in the view — it is the right SwiftData reactivity mechanism. Pass its results into
a **pure function** that returns a state struct. The view renders the struct. Light touch, no
architectural upheaval, and it is what converts ~40 UI tests into unit tests.

```swift
// View (thin)
@Query private var sessions: [WorkoutSession]
@Query private var cardio: [CardioWorkout]
var body: some View {
    HistoryList(entries: HistoryPresenter.entries(sessions: sessions, cardio: cardio))
}

// Test (headless, swift test)
func testSoftDeletedSessionsAreExcluded() { … }
```

---

## 4. Implementation

### Phase 0 — Scaffolding

1. **`CadenceCore/Package.swift`** — add two library targets and one test target. Keep
   `swift-tools-version: 5.10` and the existing platform floors.
   ```swift
   .library(name: "CadenceFeatures", targets: ["CadenceFeatures"]),
   .library(name: "CadenceFixtures", targets: ["CadenceFixtures"]),
   …
   .target(name: "CadenceFeatures", dependencies: ["CadenceCore"]),
   .target(name: "CadenceFixtures", dependencies: ["CadenceCore"]),
   .testTarget(name: "CadenceFeaturesTests",
               dependencies: ["CadenceFeatures", "CadenceFixtures"]),
   ```
2. Link both new libraries into the `Cadence` app target in `Cadence.xcodeproj`.
3. **`Clock.swift`** — `public struct Clock { public var now: () -> Date }` with `.live` and
   `.fixed(Date)`. Follow the existing pattern: `CadenceCore`'s `WorkoutClock` and
   `PhaseCountdownClock` already take an injected `now:`, which is exactly why they are testable.
   Every extracted model takes a `Clock` instead of calling `Date()` directly.
4. **`CadenceFixtures`** — lift the 15 seed builders out of `App/UITestSeed.swift`.
   `UITestSeed.apply(args:context:)` becomes a thin dispatcher over `Fixtures`. Unit tests then
   seed with `Fixtures.coachWednesdayComplete(into: context)` — *the same fixture the UI test
   used*. Move `FakeHealthProvider` here too (deterministic `seededTodaySteps = 7432`).
5. **`Makefile`**:
   ```make
   test:   cd CadenceCore && swift test          # the real gate; seconds, no simulator
   smoke:  build-for-testing once, then test-without-building, serial, one sim
   ci:     test + smoke
   ```
6. **CI** (`.github/workflows/ios.yml`) — the existing `core-tests` job picks up
   `CadenceFeaturesTests` for free. Add a `smoke` job running the ~10-test plan on the GitHub
   macOS runner, so the laptop never has to.

### Phase 1 — Pure presenters (mechanical, zero risk)

Move, then test. No behavior change.

| From | To |
|---|---|
| `Shared/Formatting.swift` | `CadenceFeatures/Format.swift` (drop the unused `import SwiftUI`) |
| `Features/Plan/AssessmentDisplay.swift` | `AssessmentDisplay` — return `TrendDirection`, not `Color`/`Image` |
| `Features/History/HistoryView.swift` → `entries` | `HistoryPresenter.entries(sessions:cardio:)` |
| `Features/Coach/YourWeekView.swift` | `YourWeekPresenter` — `weeklyZoneMinutes`, `zoneRows`, `modality(for:)`, `intensity(for:)` |
| `Features/Progress/ProgressView.swift` | `ProgressPresenter` — `strengthSeries`, `strengthTrendSummary`, `intensityRead`, `effortRead` |
| `Features/Workout/WorkoutSummaryView.swift` → `topLabel` | `WorkoutSummaryPresenter` |
| `Features/Settings/ExportView.swift` → `rebuild()` | `ExportPresenter` (`DataExport` itself is already core-tested) |

### Phase 2 — `@Observable` models

Move into `CadenceFeatures` with a `Clock` injected in place of every bare `Date()`.

- `App/ActiveWorkoutModel.swift` — start/pause/resume/`endStrength` lifecycle, `endedAt`/`updatedAt` stamping. **Currently untested.**
- `App/IntervalRunner.swift` — has 17 tests, but they run in the simulator. Moving it makes them free.
- `Features/Train/RestTimer.swift` (`RestTimerModel`) — 6 tests, same deal.
- `Features/Cardio/CardioRecorder.swift`
- `Shared/IntervalCueScheduler.swift` + `IntervalCues.swift` + `WorkoutCues.swift` — cue timing state machine (`lastWarnedPhase`, `lastTickSecond`).
- `App/AppSettings.swift` → `SettingsStore`. It already accepts an injected `UserDefaults` (`AppSettings(defaults:)`), so this is a straight lift. The app's `AppSettings` becomes a thin `@Observable` wrapper.
- `Store/StoreService.swift` → **split**. `EntitlementResolver` (pure: transactions → `ProEntitlement`, `updateTrialState`, `trialDaysRemaining`) goes to features behind a `protocol EntitlementSource`. `StoreKitEntitlementSource` (the actual StoreKit calls) stays in the app.

> **Big win:** `FR7LifecycleUITests` currently does `Thread.sleep(2.5)` four times to assert a
> timer froze or advanced (~10s of wall clock, inherently racy). With an injected `Clock` those
> become instant, deterministic unit tests.

### Phase 3 — The two monsters

Extract in **small commits** (one function group at a time), keeping the corresponding UI test
passing after each. This is the risky phase.

- **`SessionView.swift` (1,778 LOC) → `SessionViewModel`.** Takes a `ModelContext` and the
  `@Query` results; tested against an in-memory store seeded from `CadenceFixtures`. `SessionView`
  keeps `@Query`/`@Environment` and delegates.
- **`HomeView.swift` (1,135 LOC) → `HomeCoachModel`.** Make `CoachSignature` a first-class tested
  unit: *"adding a set changes the signature"*, *"a soft-deleted session changes the signature"*,
  *"a no-op does not"*. **This is the single highest-value test gained from the whole exercise.**
- **`WorkoutPlanEditor.swift` (500 LOC) → `EditablePlan`.** The four mapping functions are pure —
  ideal unit-test material.

### Phase 4 — `CoachRouter` (pure navigation)

Nine simulator tests exist solely to assert *"a coach recommendation opens the plan editor, never
a live recorder"*: `P5DoThisUITests` (3), `CoachStartRoutingUITests` (3), `AdditionalStrengthUITests`
(1), `HomeWhatYouDidNavUITests` (2). Make routing a pure function:

```swift
public enum Route: Equatable {
    case planEditor(EditablePlan), session(UUID), intervalSetup(IntervalPlan), …
}
public enum CoachRouter {
    public static func destination(for session: CoachSession, status: CoachAddOnStatus?) -> Route
}
```

The view shrinks to `switch CoachRouter.destination(for:)`. The rule becomes a one-line assertion
over every `CoachSession` kind. Do the same for `OnboardingModel` (the 4-screen state machine;
`OnboardingUITests`' 9 tests → 8 unit + 1 smoke).

### Phase 5 — Cull the XCUITest suite to ~10

Delete all 37 files; add one smoke suite. **Never delete a UI test without first landing the unit
test that replaced it.**

| Surviving test | Covers | Replaces |
|---|---|---|
| `SmokeLaunchTests.testColdLaunchShowsHomeAndTabs` | App boots, 3 tabs, Home hero renders | `P3CoachHomeUITests`, `LayoutPolishUITests`, `AboutUITests`, `HomeSimplificationUITests` |
| `SmokeOnboardingTests.testFirstRunCompletes` | `-showOnboarding`, 4 screens → Home | `OnboardingUITests` (9) |
| `SmokeStrengthLoopTests.testLogWorkoutEndToEnd` | **The core loop.** Start → Weights → Quick Start → add exercise → log a set → end → appears in History | `FR1StrengthUITests`, `FR7LifecycleUITests`, `StrengthEditingUITests`, `FR9Feedback2UITests` |
| `SmokeCoachRoutingTests.testCoachRecOpensPlanEditor` | Seeded coach card → tap → **plan editor, not recorder** → Start lands on session | `P5DoThisUITests`, `CoachStartRoutingUITests`, `CoachSurfaceUITests`, `AdditionalStrengthUITests` |
| `SmokeIntervalTests.testIntervalRunsAndSummarizes` | Real clock + audio cues: start interval, phase advances, end → summary | `FR2IntervalsUITests`, `FR2CardioUITests`, `FR12Feedback5UITests` |
| `SmokePaywallTests.testLockedUserSeesPaywall` | `-proLocked` → gate → paywall presents (StoreKit config binding) | `MonetizationUITests` (4) |
| `SmokeExportTests.testExportProducesFile` | Settings → Export → document interaction | `FR6MigrationUITests`, `FR6PolishUITests`, `FR9PolishUITests` |
| `SmokeAssessmentTests.testRecordAssessmentShowsInFitness` | Tests tab → record → Your Fitness updates | `P4AssessmentsUITests`, `CoachTestRecommendationUITests` |
| `SmokeHealthTests.testStepsRenderFromProvider` | `-todaySteps 7432` → Home shows it (provider plumbing) | `FR3StepsUITests`, `FR4DataSensorsUITests` |
| `SmokeAccessibilityTests.testHomeIsAccessible` | **NFR-2 gate.** Every Home control has a VoiceOver label; Dynamic Type XXL doesn't clip the hero | (new — currently untested) |

`AppStoreScreenshotsUITests` is a *tool*, not a test. Keep it, but move it to its own
`Screenshots.xctestplan` so it never runs as part of any gate.

#### Runner config — stop the machine-melting

- **Rewrite `Cadence/Cadence.xctestplan`:** delete `"maximumTestRepetitions": 3` and
  `"testRepetitionMode": "retryOnFailure"`. Retries were masking flakiness and tripling worst-case
  runtime. Add `"defaultTestExecutionTimeAllowance": 60` so a hang fails fast.
- **`Cadence/CadenceUITests/UITestHelpers.swift`:** cut `waitTap`'s default timeout **25s → 5s**;
  `tapToReveal` attempts **5 → 2**. Delete `dismissRestBar`'s retry loop and the
  `scrollToHittableAndTap` swipe loops if the surviving tests don't need them.
- **App under `-uiTest`: disable animations** (`UIView.setAnimationsEnabled(false)`). This is the
  single biggest wall-clock and flakiness win available and it isn't done today.
- **Build once, run serial** — parallel testing spawns N simulator clones; that, plus 148 cold
  launches, is what pins the CPU:
  ```sh
  xcodebuild build-for-testing -scheme Cadence -derivedDataPath .build/dd \
    -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
  xcodebuild test-without-building -scheme Cadence -derivedDataPath .build/dd \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1
  ```

### Phase 6 — Guardrails

1. **`scripts/check-test-pyramid.sh`**, wired into CI:
   - Fail if `Cadence/CadenceUITests/` contains more than **12** `func test`.
   - Fail if any file under `Cadence/Cadence/Features/` exceeds **400 LOC** (today `SessionView`
     is 1,778 and `HomeView` is 1,135 — the budget forces logic out of views).
   - Fail if `CadenceFeatures/` contains `import SwiftUI`.
2. **`CLAUDE.md`** — add under Conventions: *"Logic goes in `CadenceFeatures`, not in a `View`.
   Views take a prepared state struct and render it. New tests go in `CadenceFeaturesTests`
   (`swift test`); the XCUITest suite is a fixed ~10-test smoke gate and does not grow."*

---

## 5. Testing / verification

Each phase must be green before the next starts.

- **Per phase:** `cd CadenceCore && swift test`. This is the gate. Headless, seconds, never red.
- **Behavior preservation (Phases 1–4):** the extraction is a *move*, so before deleting each UI
  test in Phase 5, run the **old** UI test against the refactored app and confirm it still passes.
  That is the proof the extraction didn't change behavior. Only then delete it.
- **Phase 5 exit:** `make smoke` completes serially in **under 5 minutes** with **zero retries** on
  a cold simulator. If any smoke test needs a retry to pass, it is testing the wrong thing — push
  its assertion down into a unit test.
- **Final:** `swift test` **791 → ~1,050–1,100** tests; XCUITest **148 → 10**; `make test` (the
  everyday gate) needs **no simulator at all**.

If the simulator degrades mid-run (launches ballooning to ~45s, `no debugger version`), that is the
known environment fault — `killall -9 com.apple.CoreSimulator.CoreSimulatorService`, re-run, and
report honestly which failures were real vs. environmental (per `CLAUDE.md`).

---

## 6. Phased rollout

| Phase | Branch | Depends on | Risk |
|---|---|---|---|
| 0 — Scaffolding (`Package.swift`, `Clock`, `CadenceFixtures`, Makefile, CI) | `test-pyramid-0-scaffold` | — | low |
| 1 — Pure presenters | `test-pyramid-1-presenters` | 0 | low (mechanical) |
| 2 — `@Observable` models | `test-pyramid-2-models` | 0 | low–medium |
| 3 — `SessionViewModel` + `HomeCoachModel` + `EditablePlan` | `test-pyramid-3-viewmodels` | 1, 2 | **high** — stack on 1+2, small commits |
| 4 — `CoachRouter` + `OnboardingModel` | `test-pyramid-4-routing` | 3 | medium |
| 5 — Cull UI suite to ~10 smoke + runner config | `test-pyramid-5-smoke` | 1–4 | medium |
| 6 — Guardrails | `test-pyramid-6-guardrails` | 5 | low |

Schema changes: **none.** All `@Model` types stay in `CadenceCore` untouched, so the local store
and older JSON exports keep working.

## 7. Risks / open questions

- **Phase 3 is the risky one.** `SessionView` and `HomeView` are large and load-bearing. Extract one
  function group per commit; keep the old UI test green after each; delete it only at the end.
- **`CadenceFixtures` ships in the release binary** (~350 LOC of data builders) because SwiftPM
  can't easily link a target by build configuration. Acceptable cost for one shared fixture catalog;
  the alternative (duplicating the seeds) is worse. Revisit if binary size matters.
- **`CadenceFeatures` must not import SwiftUI.** If an extraction wants a `Color` or a `View`, that
  is the signal to return a semantic enum instead.
