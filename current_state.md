# Current State — Cadence field-testing redesign

Live handoff/progress tracker. Read this first, then
`plans/field-testing/2026-06-11/round4-plan.md`.

_Last updated: 2026-06-11 — round 2/3 + round-4 sounds MERGED to `main`; UI suite green._

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

## NEXT (round 4 — see plans/field-testing/2026-06-11/round4-plan.md)
**Part A (implement next, user EMPHASISED summary + history):**
1. Universal Pause/Resume + End on EVERY workout type incl. during the countdown.
2. End → "Are you sure?" confirmation.
3. Always show a **WorkoutSummaryView** at end (cardio + strength).
4. Unified workout history (a walk saved as `CardioWorkout` didn't show in the
   strength-only "Recent workouts" — make history merge strength + cardio).
5. History row → tap → the summary page.
6. Apple-Watch HR backfill: query HealthKit for HR samples in the workout window
   (`HealthDataProviding.heartRate(in:)`) and attach to the `CardioWorkout` when no
   strap HR was captured (the phone can't stream the Watch's live HR by design).
7. ✅ Sounds (done above).

**Part B (designed, build after A):** CrossFit — a `WorkoutPlan`/`PlanItem` core
model, 15 benchmark "Girls" workouts (researched, in the plan doc), a
`WorkoutType.crossfit` picker, CrossFit movements in the §03 library + a
movement-guide link, and a "WOD of the day" Home card fetched from
`crossfit.com/<YYMMDD>`.

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
