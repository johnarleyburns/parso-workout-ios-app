# Current State — Cadence field-testing redesign

Live handoff/progress tracker.

_Last updated: 2026-06-24 — Coach expert-system fix (plan adherence, same-day repetition
protection, tomorrow preview, citation rotation)._

## Repo / branch
- Repo: `/Users/arley/github/parso-workout-ios-app`
- **`main`** = All prior phases merged. Builds + runs clean.
- Audio/coach/refresh/routing/wakelock stream merged to `main`, plus
  D4 cardio-type-fidelity, plus coach-expert-system fix (plan adherence).
- **CadenceCore: 357/357 green; iOS build: green.**

## What just shipped — Coach expert-system fix
- **Plan adherence.** `CoachDecision.planAdherence` distinguishes planAhead / planComplete /
  offPlan. When today's planned session is complete, the Coach card shows "On plan" with a green
  checkmark, describes what was logged today, and previews tomorrow's session. The Start button
  is replaced by an acknowledged "On plan" banner.
- **Session matching.** `eventSatisfiesCoachSession` matches completed TrainingEvents to
  CoachSession candidates by kind, modality, and duration (≥75% of planned minimum). A 44-min
  boxing workout satisfies a planned 20-30 min moderate-aerobic boxing session.
- **Same-day repetition damping.** `sameDayDamping` penalizes same-modality candidates after
  completion (40 points for exact modality match, 15 for same-kind aerobic). Boxing preference
  still works on fresh days but prevents boxing-after-boxing.
- **WeeklyPlan future days.** Extended from `-6...0` to `-6...+6` days. Added `tomorrow` and
  `today` computed properties, `isFuture` flag. Tomorrow preview is surfaced in the Coach card's
  completed state.
- **Tomorrow preview.** `generateTomorrowPreview` checks strength/aerobic floor, recovery gates,
  and hard-day streak to suggest "Strength session", "Cardio session", "Rest or light activity",
  or "Recovery — strength eligible in ~Xh".
- **WhyThisToday restyle.** Removed all-caps tracked section labels; compact "What you did" rows
  with smaller icons and less padding; compact 3-column weekly metrics; removed generic "Policy"
  section. Citations now inline with claims using `EvidenceClaim` rotation.
- **Citation pools + rotation.** `CitationPool` with deterministic rotation (stable per date+claim,
  varies across days). `aerobicPool` (5 published research citations, no guideline/authority IDs)
  and `recoveryLoadPool` (6 citations). 7 new `Citation` entries added to `CitationRegistry` and
  `CITATIONS.md`.
- **Tests:** 11 new core tests (Wednesday regression, same-day suppression with/without
  preference, future WeeklyPlan, tomorrow preview, 4 citation pool tests). 1 new UI test
  (complete banner on Home). 357/357 green.
- **UI seed:** `coachWednesdayComplete` — Monday full-body + 18-min run, Tuesday rest, Wednesday
  44-min boxing → Coach shows completed state.

## Previous phases (historical reference)
- **D4 implemented (was deferred).** Boxing now carries its own `CoachSession.AerobicModality.boxing`
  (added to `AerobicModalityStorage` + conversions, Codable-safe), so selecting boxing records a
  **boxing** preference (not `.other`) and Coach recommends it next. Same fidelity holds for run /
  swim / cycle / row. `CoachAlternativesView` icon + impact-pill switches handle `.boxing`.
  3 new core tests (boxing/swim remember→recommend loop + Codable round-trip). 346/346 green.
- **Warm-up-overlay bug root-caused & FIXED.** The "broken warm-up" was never a rendering/race bug:
  the `GuidedPhaseOverlay` *did* render ("Warm Up" / countdown / Pause / Skip), but every element's
  accessibility id was clobbered to `tab.workout`. `RootTabView` applied
  `.accessibilityIdentifier("tab.workout")` (and `tab.tests`/`tab.progress`) to the whole tab
  **content** view; that id leaked onto the ZStack-sibling overlays (warm-up / get-ready countdown /
  HR gate) that sit outside the NavigationStack, overriding `warmup.*` (and `countdown.*`/HR-gate)
  ids. Fix: move each tab identifier onto its `tabItem` `Label` so it identifies the tab **button**,
  not the content subtree. No test references the `tab.*` ids; tab switching is by label and
  unaffected (`P3/testTabBarHasThreeTabs` green). Now green: `FR11/testStartWithWarmUpThenSession`,
  `FR11/testWarmUpPauses`, and new `P5/testCoachStrengthStartRunsWarmUpThenLogger` (the full
  Coach plan → warm-up → logger chain), plus routing/setup-first P5 tests.
- **Pre-existing stale UI tests CLEANED UP.** Found while fixing P5; all now green:
  - The deeper cause of the FR10/FR7 failures: the guided **warm-up default (5 min) leaked into
    UI-test mode** (only `preWorkoutCountdown` was zeroed in `-uiTest`, not `warmupMinutes`), so any
    `editor.start` from a library preset ran a 5-min warm-up and the session never appeared in 25s.
    Fix: zero `warmupMinutes` in `-uiTest` with a `-warmupMinutes N` opt-in (mirrors `-preCountdown`).
  - `FR11/testStartWithWarmUpThenSession` + `testWarmUpPauses` now opt in via `-warmupMinutes 1`.
  - `FR10/testStrengthLibraryCustomRepScheme`: dead `plan.preview.start` → `editor.start`
    (`customRep.continue` already routes to the plan editor).
  - `FR7/testCountdownPause`: rerouted off dead `plan.preview.start` to Quick Start → editor → the
    get-ready countdown (with `-preCountdown 30`). Also confirms the RootTabView fix un-clobbered
    `countdown.*` ids, not just `warmup.*`.
  - `P3/testQuickActionLogOpensPicker`: `log.strength`/`log.cardio` → `logType.strength`/`logType.other`.
  - `P3/testQuickActionProgramsNavigates`: `planning.title`/`planning.view` → `planning`.
  - Deleted dead `PlanPreviewView` (defined but never instantiated; was the only thing referencing
    `plan.preview.*`).
  - **Anti-flake hardening:** the FR11/FR7 sheet-open taps used a single `waitTap()` that drops
    silently on a degraded simulator (element tapped, sheet never opens). Added a `tapToReveal(src,
    dst)` helper (re-taps the source until the destination appears, only while the source is still
    hittable so it never taps through an opened surface) and routed every FR11/FR7
    navigation/transition tap through it. Green ×2 back-to-back on a fresh sim.

## What just shipped — Audio / Coach freshness / Coach Start routing / wakelock
- **A. Non-interrupting audio.** New `WorkoutAudioSession.configureForCues()` (`.ambient` +
  `.mixWithOthers`, never `.duckOthers`). `WorkoutCues` + `IntervalCues` route all beeps/bells/
  speech through it; ducking + `notifyOthersOnDeactivation` removed. Background music/podcasts
  no longer pause or dip during warm-up/exercise/intervals. Grep gate clean (only a doc comment).
- **B. Coach freshness.** `CoachFacts.make` now builds `completed` as past-only (`end <= now`),
  sorted ascending; all rolling windows + thisWeek are explicitly lower/upper bounded (future-safe).
  `CoachDecision` last-strength/last-cardio use `max(by: end)` (newest by end date) instead of
  `.last(where:)`. Fixes wrong "Why this today" recency when Home supplies events newest-first.
- **C. Post-save Home refresh.** `HomeView` replaced the unused `coachDayToken` with a read
  `historyRefreshToken`; `markWorkoutHistoryChanged()` (yields a main-actor turn, then bumps the
  token) is called from every cardio `onSaved` (Record/Outdoor/Interval/Swim), `LogWorkoutPicker`,
  HealthKit ingest (when >0), and delete paths. The four cardio views gained an `onSaved` callback.
  This Week / Coach card / Why-this-today update immediately, no app re-entry.
- **D. Coach Start routing = setup-first.** CTA copy now "Start" for all trainable picks (rest/
  recovery keep bespoke copy); CTA id is `home.coachStart`. `launchDecision` routes run/walk/cycle →
  `CardioGoalSheet`, swim → `SwimRecordView` setup, hiit/**boxing** → `IntervalSetupView`, rowing/
  other → new `TimerCardioSetupView`, strength → `WorkoutPlanEditor`. Boxing no longer falls back to
  generic Other cardio.
- **Wakelock (user request).** New `.keepAwake()` modifier disables auto-lock during live
  workouts, warm-up, and cool-down (`SessionView`, `RecordCardioView`, `OutdoorCardioView`,
  `IntervalView`, `SwimRecordView`, `GuidedPhaseOverlay`); restored on disappear.
- **New files:** `WorkoutAudioSession.swift`, `KeepAwake.swift`, `TimerCardioSetupView.swift`
  (+`TimerCardioSetup`), `CoachStartRoutingUITests.swift`, `HomeRefreshUITests.swift`.
- **New seeds:** `coachYesterdayMixedHistory`, `coachBoxingPrimary`, `coachRunPrimary`,
  `coachStrengthPrimary`. (Note: seed preference JSON `updatedAt` must be a numeric Double, not
  ISO8601 — the decoder uses the default `.deferredToDate` strategy.)
- **Tests:** 6 new core tests (CoachFacts ordering/future-safe + CoachDecision newest-by-end).
- **D4:** initially deferred (boxing as `.other`), then implemented as a follow-up — boxing now
  has its own `.boxing` modality for full preference fidelity (see the D4 section above).
- **Pre-existing, out of scope:** some older `P3CoachHomeUITests` assert removed card ids
  (`coach.card.why/target/action/citation`) from a prior card design — those fail independently of
  this work. The Coach-strength editor→warm-up→logger downstream plumbing is unchanged and not
  re-tested here.

## What just shipped — Coach Why This Today + Preferences
- **`ObservedFact` replaced** with rich model (`Kind`, `title`, `value`, `detail`, `occurredAt`). Last Cardio added. Summary facts use static values, never `Text(date, style: .relative)`.
- **Duplicate Evidence section removed.** Citations are inline-only; no generic Evidence header when claims carry their own science links.
- **COACH'S PICK section** added directly below What you did, showing the actual prescription (title, duration, modality, intensity, target grid).
- **Alternatives flow:** `alternatives >` opens `CoachAlternativesView` with eligible full-match / closest-match options. Selecting an alternative launches it and records a `CoachPreferenceEvent`.
- **`CoachPreferenceProfile`** (new file in CadenceCore) — Codable profile stored in UserDefaults via `AppSettings.coachPreferenceProfile`. `CoachDecisionEngine.run` now accepts profile and adjusts scoring after eligibility gates. Preferences reorder eligible candidates but never override pain, active-workout, recovery, or lower-body-collision gates.
- **Expanded aerobic candidates:** Easy swim/row, moderate cycle/swim/row/boxing now available alongside walk/run.
- **Export v2:** `CadenceExport` version 2 includes optional `coachPreferences: ExportCoachPreferences?`. Old v1 exports still decode (preferences nil). `ExportView` passes `settings.coachPreferenceProfile.exportDTO`. Footer copy updated.
- **UI test seeds:** `coachWhyMixedHistory`, `coachAerobicGap`, `coachCyclePreference`, `coachLowerBodyRecovery`.
- **Tests:** 15 new core unit tests (CoachDecisionEngine + CoachPreferenceProfile + DataExport). 4 new `WhyThisTodayUITests`. Fixed 2 pre-existing build errors in `UITestHelpers.swift` (duplicate `keypadEnter`, `XCUIKeyboardKeyDelete`).
- **New files:** `CoachPreferenceProfile.swift` (core), `CoachAlternativesView.swift` (app), `CoachPreferenceProfileTests.swift` (tests), `WhyThisTodayUITests.swift` (tests).
- **No LLM, no telemetry, no accounts, no server.** Purely deterministic, local, cited.

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
- `CoachPreferenceProfile` stored as JSON `Data` in UserDefaults under key
  `settings.coachPreferenceProfile` (not SwiftData). Cleared in `-uiTest` mode.
