# Current State — Cadence field-testing redesign

Live handoff/progress tracker. Read this first, then
`plans/field-testing/2026-06-11/round4-plan.md`.

_Last updated: 2026-06-12 — 4A-1 MERGED (#14), 4A-2 MERGED (#15); 4A-3 always-show summary in progress on `feat/ft4a-summary`._

## Repo / branch
- Repo: `/Users/arley/github/parso-workout-ios-app` (this is the user's working copy).
- **`main`** = Phases 1–6 + round 2/3 Home-dashboard rebuild + intervals + round-4
  A7 sounds, all merged. The app on `main` builds + runs clean.
- **UI suite: 27/27 green; CadenceCore: 95/95 green** (verified 2026-06-11 on a
  freshly-restarted iPhone 16 sim, non-parallel).
- **Next branch to cut: `feat/ft4a-pause-summary`** off `main` for Round 4 Part A.

## What's DONE on this branch (uncommitted, builds green)
- **Pre-workout countdown** (`PreWorkoutCountdownView`, default 30s, Skip/Cancel;
  setting `settings.preWorkoutCountdown`; uiTest defaults to 0 unless `-preCountdown N`).
- **Session screen**: "Use Previous Workout" (copies a full past workout —
  `WorkoutRepository.copyWorkout`); Add Exercise moved to the bottom.
- **Home dashboard rebuild** (`HomeView`): simple step count + workouts-this-week,
  Start Workout hero (gradient), inline 7-day trend, inline Recent cardio + Recent
  workouts with "See all" links (`home.stats`/`home.train`/`home.cardio`,
  `home.cardioRow.*`, `home.sessionRow`). Step RING removed; 7-day chart also added
  to Stats (`TrendsView`) which gained a `stats.cardio` link.
- **Intervals**: 4 new science-backed protocols in core (`gibala`, `sit`, `rehit`,
  `tenTwentyThirty`) + factories tested; `IntervalSetupView` now SELECT-then-START
  (`interval.start`, no auto-launch); `IntervalView` shows the protocol name
  persistently (`interval.planName`).
- **Boxing/interval sounds** (round-4 A7): bundled `Cadence/Cadence/Sounds/
  opening-closing-bell.mp3` (round start/end) + `warning-bell.mp3` (fires once at
  30s left of a work phase); `IntervalCues` plays them via `AVAudioPlayer` + haptics.
- **WorkoutTypePicker**: visual `WorkoutHero` cards (type-keyed gradients + glyph,
  optional `hero-<type>` image asset slot).
- `CadenceCore`: **95 tests green** (incl. new interval + copyWorkout tests).
- iOS **build: green**.

## DONE — round-2/3 UI suite is green and merged
**Two root causes fixed (was 18/27 red → 0 red):**
1. **Plain-button + `Spacer()` activation point (14 of the failures).** The Home
   "See all" headers/rows were `.buttonStyle(.plain)` wrapping `HStack { …; Spacer();
   … }`. XCUITest puts a button's activation point at the frame CENTRE → it landed
   on the empty `Spacer()` (non-interactive) → tap rejected ("Failed to compute hit
   point … Activation point invalid") → no navigation. **Fix:**
   `.contentShape(Rectangle())` on `sectionHeader`, `home.cardioRow`,
   `home.sessionRow`, `home.resume`. (Also converted HomeView to a single
   `NavigationPath` — fixed a latent mixed-`navigationDestination` bug too.)
2. **TrendsView lazy-List below the fold (1 failure).** The new 7-day activity chart
   was added at the TOP of TrendsView, pushing the "Exercises" section below the
   fold. `FR5TrendsUITests.testExerciseTrendAndPRs` waited for `trends.exercise.Bench
   Press` to *exist* without scrolling — off-screen lazy-List rows aren't in the AX
   tree. **Fix:** test now uses `scrollToAndTapButton(...)` to bring the row in.
- The other 3 originally-red tests (FR4 `testSaveStrengthToHealth` keyboard focus,
  FR6 `testImportGmailDraft`, FR6 `testPolishSettingsPresentAndPersist` toggle tap)
  were **degraded-sim flakiness** — they pass on a freshly-restarted sim. Watch for
  Mach error -308 "server died"; restart CoreSimulator and re-run.

Merged to `main` via fast-forward (established pattern). Next: Round 4 Part A.

## NEXT — Round 4 Part A (minus watch), build-ready plan in `round4a-plan.md`
**THE PLAN TO EXECUTE:** `plans/field-testing/2026-06-11/round4a-plan.md` — it has
the data-model deltas, cross-cutting decisions, and a 4-phase rollout with unit +
integration + UI tests per phase. Scope confirmed by the user 2026-06-11:

**In scope (build these, in order — one branch+PR each, stacked):**
- **4A-1 ✅ MERGED (PR #14)** CadenceCore `WorkoutSummaryData` +
  `WorkoutHistoryEntry`/`unifiedHistory` (+ 9 unit tests). `swift test` 104/104.
- **4A-2 ✅ MERGED (PR #15)** Universal Pause/Resume + End incl. countdown (A1) + End
  "Are you sure?" (A2) via reusable `WorkoutControlBar`. `swift test` 104/104; UI 29/29.
  `Features/Shared/WorkoutControlBar.swift` (owns confirm dialog, `idPrefix` per
  screen, `workout.endConfirm`/`workout.endCancel`);
  `ActiveWorkoutModel.pause/resume/isPaused`; SessionView End→bar (`workout.*`) +
  idle watchdog freezes while paused; outdoor/record/interval on the bar (keep
  `outdoor.*`/`record.*`/`interval.*` ids); countdown `countdown.pause`. FR2 end
  flows tap `workout.endConfirm`. `FR7LifecycleUITests`.
- **4A-3 (in progress)** Always-show `WorkoutSummaryView` after End, all types (A3).
  Branch `feat/ft4a-summary`. New `Features/Workout/WorkoutSummaryView.swift`
  (`summary.title/duration/metric.*/exercise.*/hrChart/map/done/saveHealth`).
  Cardio/interval swap their live view for the summary inside the same cover after
  save (`summary.done` dismisses); strength presents it as a cover over SessionView,
  Done pops home. New FR7 tests: cardio/strength/outdoor summary.
- **4A-4** Unified strength+cardio history + row→summary (A4, A5). Branch
  `feat/ft4a-history`. Adds `-seed historyMixed`. New `FR7LifecycleUITests`.

**DEFERRED (do NOT build now):**
- **A6 Apple-Watch HR backfill + ALL watch integration** — later.
- **Part B CrossFit** (WorkoutPlan model, 15 benchmark "Girls", crossfit type,
  movements, WOD-of-the-day card) — future. Design stays in `round4-plan.md`.

A7 sounds = already done & merged.

## How to work here (methodology — also in CLAUDE.md)
- Plan to disk first for big asks (`plans/field-testing/<date>/`); implement
  phase-by-phase, one PR each; update THIS file at each phase start.
- Logic in `CadenceCore` (`swift test` — reliable). UI via `xcodebuild` (flaky on a
  degraded sim).
- **Degraded-sim gotcha:** if `xcodebuild test` launches balloon to ~45s with
  `no debugger version`, restart CoreSimulator:
  `xcrun simctl shutdown all; killall -9 com.apple.CoreSimulator.CoreSimulatorService`
  then boot the device again. Run non-parallel for reliable signal.

## Commands
- Core tests: `cd CadenceCore && swift test`
- Build: `xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence -destination 'id=FC7B2F90-A27B-4BD5-9313-7B267636E165' build`
- UI suite (non-parallel): same with `-parallel-testing-enabled NO test`
  (sim id `FC7B2F90-A27B-4BD5-9313-7B267636E165` = iPhone 16; pick any booted one).
- Inspect a failure: `xcrun xcresulttool get test-results test-details --test-id 'SuiteName/testName()' --path <latest .xcresult>`

## Notes / decisions in effect
- All merges to `main` so far were fast-forward; PRs #7–#13.
- Schema changes additive + CloudKit-safe; `[String]` model attrs are delimited-
  String-backed (`StringArray`) — do NOT reintroduce raw `[String]` `@Model` attrs.
- `opening-closing-bell.mp3` / `warning-bell.mp3` also sit in the repo root (source
  copies); the bundled copies are under `Cadence/Cadence/Sounds/`.
