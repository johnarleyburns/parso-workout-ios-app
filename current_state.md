# Current State — Cadence field-testing redesign

Live handoff/progress tracker.

_Last updated: 2026-07-14 — three coach-recommendation fixes from the 2026-07-14 export analysis (exercise variety, bodyweight reps, plan modality labels)._

## Coach fixes — 2026-07-14 export analysis (`plans/…/examine-cladiron-export-2026-07-14…`)

- **Fix 1 — cross-day exercise variety (shipped 2026-07-14, `a339c64`).** The plan
  optimizer pinned one exercise per movement pattern (most-trained in 28d), so a
  chronically below-MEV part (abs) resolved to "rotary torso" on every planned day.
  `CoachSession.trainedExerciseCandidates(facts:)` now exposes the *ranked*
  per-pattern list (`mostTrainedExercises` = its `.first`); `CoachPlanOptimizer`
  threads the running set of already-assigned exercises through
  `plan → chooseSession → optimizedVersion → reshapedExercises`, and
  `rotatedForVariety` swaps an already-used identity for an equivalent alternative
  (exact same covered body parts → coverage/MRV math unchanged; recovery-eligible;
  user's own trained lifts preferred, then catalog defaults). Compounds with unique
  coverage stay put; interchangeable isolation rotates. New
  `CoachExerciseVarietyTests` (2).
- **Fix 2 — bodyweight-aware rep prescription (shipped 2026-07-14, `9e0b7d4`).**
  Reps came entirely from `TrainingGoal.repRange` (hypertrophy → 12/10/8 ladder)
  regardless of movement type — wrong for a user logging 40/30/20/10 crunches.
  `PrescriptionMath.repRange(forExerciseNamed:goal:recentTopReps:)`: bodyweight
  moves track the user's real logged top set (upper = recent top reps, lower ≈60%);
  clearly high-rep moves (unloaded core, air squats) default to **15–25** absent
  history; time holds (plank) and weighted lifts keep the goal range. Threaded
  through `strengthExercises`/`buildStrengthExercises`, `CoachPlanOptimizer.copy`
  (+ `bestExercise` fallbacks) and the variety rotation.
  **Intentional deviation from the plan:** the `progression`/`deload`
  `topSetWeightKg > 0` gates were left alone — `LiftSnapshot`s are only built from
  loaded sets, so weight-0 movements never reach those rules; the visible bad
  prescription originates in the session builders, which is where the fix landed.
  New `CoachBodyweightPrescriptionTests` (6).
- **Fix 3 — past plan days carry the real cardio modality (shipped 2026-07-14, `ecaf702`).**
  `WeeklyPlan.generate` flattened logged aerobic events into generic buckets, so a
  logged Boxing session (no HR → non-vigorous) read "Easy aerobic".
  `cardioEventsByDay` now captures `AerobicEventDetails.Modality.displayName`
  (in-memory, additive; `.other` falls back to generic); past-day labels prefer it,
  future prescribed days keep the generic bucket. `WeekStripView`/`YourWeekView`
  render labels verbatim — no view changes. Also fixed a latent nondeterminism:
  multi-pattern movements are now attributed to a pattern in stable sorted order
  (Set iteration is hash-seeded per process). New `WeeklyPlanModalityLabelTests` (3).
- **Follow-up (`f975e4f`):** pre-existing app-target build break from `74d8e28`
  (`allPeople` still `private` while `SessionView+Partners.swift` uses it) fixed —
  unrelated to the coach work but blocked the integration build.
- `swift test` **1037 → 1048**, verified stable across repeated runs; app-target
  `xcodebuild` green; test-pyramid guardrail green (uitests 11/12, no growth).

## Revenue plan (`plans/revenue/2026-07-13/`)

- **"Your Plan" row polish (2026-07-13).** `YourWeekView` day rows (shared
  `CoachPlanDayRow`, so both **This Week** and **Planned (next week)** get it):
  today's row in This Week now has a light-blue `.listRowBackground(Color.blue.opacity(0.12))`
  as an orientation aid, and the weekday-abbreviation column widened `32 → 44pt`
  with `.lineLimit(1)` so "Mon"/"Wed" never wrap at larger Dynamic Type. The
  same-day-cardio **timing note** ("later in the day" / "after lifting") is gone —
  removed at the source in `WeeklyPlan.futureSessions` (no longer populated; the
  `sameDayCardioTiming` *preference* stays for schedule setup) and from all three
  displays (`CoachPlanDayRow`, `TodayPlanRow`, `PlannedDayPreviewView`). Core test
  `testTwoADayCardioTimingNote` → `testSameDayCardioHasNoTimingNote` (asserts notes
  are now always nil, two-a-days still pair strength+cardio). `YourWeekView`
  406 → 401 LOC (under grandfathered ceiling). `swift test` unchanged at **1037**;
  xcodebuild + both guardrails green.
- **UI polish follow-up (2026-07-13).** Phase-6 Progress "Personal records" card: removed
  the per-row leading trophy/sparkles icon, and pinned the Swift Charts legend to the
  bottom of the plot (`.chartPlotStyle` fixed height + `.chartLegend(position: .bottom)`)
  so the multi-lift exercise-name legend no longer overflowed the fixed frame and
  overlapped the PR list below. Home "This Week" strip (`WeekStripView`): a blue
  rounded-rectangle stroke now surrounds today's cell (day letter + circle) as an
  orientation aid; uniform vertical padding on every cell means no layout shift. UI-only;
  `swift test` unchanged at **1037**; xcodebuild + both guardrails green.
- **Phase 6 — acquisition loop: PR timeline, consistency heatmap, shareable PR card (shipped 2026-07-13).**
  Decision D6. Cladiron had no growth loop — every install earned from scratch — but
  a social feed needs accounts + a server and would destroy the positioning. Ships the
  10% that captures the value: something worth sharing and a way to share it, **at zero
  privacy cost**. Also makes two long-standing `CLAUDE.md` Progress-IA claims true (PR
  timeline + consistency heatmap never existed; PR logic lived inline in `SessionView` /
  `WorkoutRepository.currentPR`). New pure `PRTimeline.swift` (`PREvent`/`PRKind`,
  `events`/`latestPerExercise`) lifts PR-detection onto `PRCalculator` + `PRRule` so the
  timeline and the in-session PR badge can never disagree; `WorkoutRepository.prSetSamples`/
  `prEvents` bridge live sessions (owner-only, same `isOwnerSet` filter as the badge). New
  pure `ConsistencyHeatmap.swift` (`HeatmapDay`, `days`/`currentStreak`/`longestStreak`)
  takes `Calendar` as a parameter and walks day-by-day via the calendar (not fixed 86 400 s)
  so DST/timezone bucketing is correct. `CadenceFeatures` presenters `PRTimelinePresenter`
  (semantic `Accent`: firstEver/improvement) + `ConsistencyHeatmapPresenter` (semantic
  `Shade` ramp 0…4) — **no `Color` in Features** (guardrail-enforced). UI: `PRTimelineView`
  (Swift Charts stepped progression + trophy-shelf rows), `ConsistencyHeatmapView`
  (GitHub-style week grid + streak headline), both cited (`oneRMEstimation`/`frequencyMeta`),
  linked into the Progress tab. The loop: `Features/Share/ShareCardRenderer.swift` renders a
  branded `PRCard` through `ImageRenderer` → PNG in the temp dir → `ShareLink` — **no account,
  no server, nothing leaves the device but an image the user chose to post.** `CLAUDE.md`
  Progress IA + README restored (PR timeline + consistency heatmap now true). New tests:
  `PRTimelineTests` (12), `ConsistencyHeatmapTests` (11, incl. DST spring/fall + timezone),
  `PRTimelinePresenterTests` (6), `ConsistencyHeatmapPresenterTests` (6). `swift test`
  **1005 → 1037**; xcodebuild + both guardrails green (no new UI tests, uitests 11/12).
- **Phase 5 — automatic iCloud backup + restore, kills the data-loss 1-star (shipped 2026-07-13).**
  Decision D5. Local-only storage + a *manual* JSON export meant the first user to
  lose/replace a phone writes "it deleted my entire training log." Ships the low-risk
  half: **automatic backup of the existing `CadenceExport` v5 `.json.gz` blob to the
  user's private CloudKit** — NOT live SwiftData↔CloudKit sync. Reuses
  `DataExport`/`WorkoutRepository.merge` wholesale, leaves the SwiftData schema
  untouched (no migration risk), keeps the **Data Not Collected** label (data lives
  in the *user's own* iCloud; Apple is the processor; Cladiron never sees it). New
  pure `BackupPolicy.swift` holds all decision logic (`shouldBackUp` ≤1/day + only
  when the store changed; `restoreDecision` → `.autoRestore` only when local is
  empty, else `.offerRestore` — never silently clobbers). New app-layer
  `CloudBackupService` (`@Observable @MainActor`) does the `CKContainer`/`CKAsset`
  I/O it's told to; never blocks a workout. `AppSettings` gained additive
  `iCloudBackupEnabled` (default on), `lastBackupAt`, `lastLocalChangeAt`.
  `RootTabView` auto-restores on a fresh install, offers restore (alert) when local
  data exists, backs up opportunistically on launch + scene-active, and marks the
  store dirty on `.workoutHistoryChanged`. Settings gained an "iCloud Backup"
  section (toggle + last-backed-up + Back Up Now + Restore) with privacy-explicit
  copy. iCloud/CloudKit container added to `Cadence.entitlements` (no
  `aps-environment`/remote-notification — deliberately kept off). New
  `BackupPolicyTests` (10, incl. `test_nonEmptyLocalNeverSilentlyClobbered`).
  `swift test` **995 → 1005**; xcodebuild + both guardrails green. **CI note:** the new
  iCloud container entitlement (`iCloud.guru.parso.ios-workout-app`) failed the
  TestFlight `Archive` on the first push (the App Store provisioning profile lacked the
  iCloud capability). Resolved by regenerating the profile with the iCloud container in
  the Apple Developer portal and updating the `PROVISIONING_PROFILE_BASE64` CI secret;
  re-dispatched `main` build is fully green (core-tests ✓, testflight-build ✓).
- **Phase 4 — passive readiness fusion, the $79.99/yr wedge (shipped 2026-07-13).**
  Decision D4. The coach's readiness input was a self-report survey that never got
  filled out, while the Watch was already writing HRV/sleep/RHR to HealthKit that
  `HealthKitProvider` read *none* of. New pure `PassiveReadiness.swift`
  (`PassiveReadinessAnalyzer`) turns a window of HealthKit samples into a
  conservative, citation-backed signal: **≥14 days of HRV required** or
  `.insufficientData` (the DEFAULT — a two-day-old install makes NO claim); 7-day
  rolling mean vs 28–60d baseline; HRV < −10%/−20%, RHR ≥ +5bpm, sleep debt ≥ 2h or
  < 6h absolute contribute. New `ReadinessFusion.swift` encodes **D4**: a fresh (≤24h)
  self-report is authoritative (`sawMonitoring2016` — self-report trumps objective
  monitoring), passive fills the gap at *lower* confidence, and
  `.stronglySuppressed` + no check-in raises `promptCheckIn` (asks, never assumes).
  `ReadinessSnapshot` gained additive `passive`/`promptCheckIn`; `CoachFacts.make`
  and `CoachSnapshotBuilder.build` thread `passiveSamples` + fuse; the existing
  deferral/deload gates consume `readiness` unchanged. `HealthKitProvider` reads
  HRV SDNN / resting HR / body weight / sleep analysis (on-device, **Data Not
  Collected label unaffected**), Info.plist purpose string updated. Headless
  `PassiveReadinessPresenter.display(for:)` returns nil when `citationIds` are empty
  (mechanically enforces the HARD RULE); `PassiveReadinessCard` renders the line +
  `CitationLink`. 4 new citations (`javaloyesHRVGuided2019`, `vesterinenHRVGuided2016`,
  `buchheitMonitoring2014`, `cravenSleep2022`) added to registry + `recoveryMonitoringPool`
  + usageReasons + `docs/CITATIONS.md`; `sawMonitoring2016` now also cites the fusion
  rule. `coach-kb-version.json` **2026.4.0 → 2026.5.0**. `HomeCoachSnapshot` extracted
  from HomeView into its own file (carries `readiness`); Home reads samples off the
  render path and rebuilds on `.onChange(of: passiveSamples)`. New tests:
  `PassiveReadinessAnalyzerTests` (14), `ReadinessFusionTests` (7),
  `PassiveReadinessPresenterTests` (7), +CoachFacts/Citation/KB additions. `swift test`
  **962 → 995**; xcodebuild + both guardrails green.
- **Phase 3 — bundle exercise imagery, NFR-3 now enforced (shipped 2026-07-13).**
  Decision D3. Exercise photos were fetched from `raw.githubusercontent.com` at
  runtime (`AsyncImage`) — no images offline, and a request per exercise view in an
  app whose pitch is "we never phone home." New `scripts/build-exercise-images.sh`
  (one-shot, macOS `sips`, pinned to free-exercise-db commit `b0eed06`) downloaded
  all **1,746 images (873 × 2)**, downscaled to ≤400px HEIC q70, committed to
  `Resources/ExerciseImages/<id>/{0,1}.heic` — **30 MB** (under the 50 MB stop
  threshold). `Package.swift` copies the dir; new `ExerciseImageCatalog` resolves
  from `Bundle.module`; `ImportedExerciseLibrary` lost the `raw.githubusercontent`
  URL builder (`imageURLs(forImageName:)` is now file-based); `ExerciseDetailView`
  replaced `AsyncImage` with `UIImage(contentsOfFile:)` + placeholder. New
  `scripts/check-no-network.sh` bans fetching APIs (URLSession/AsyncImage/etc — not
  URLs) and is wired into CI next to the pyramid guardrail. New
  `ExerciseImageCatalogTests` (7). `swift test` **955 → 962**; xcodebuild + both
  guardrails green.
- **Phase 2 — launch-blocking correctness (shipped 2026-07-13).** Fixed the bug
  where **paying subscribers were shown the "Unlock the Coach" upsell**:
  `HomeView` passed `isPro: false` as a literal into `CoachUpsellPolicy`, making its
  `guard !isPro` early-return unreachable. Lifted the decision into
  `HomeCoachModel.upsellCTAVisible(entitlement:lastShown:)` (headlessly tested) and
  changed the Home call site to thread `store.entitlement` — no boolean literal at
  the call site. Deleted dead `Cadence/Cadence/Features/Coach/CoachGate.swift`
  (`CoachGate`/`CoachLockedView` were never instantiated; the real gate is
  `CoachSurfacePresenter`). New `HomeCoachModelTests` cases (6), including the
  regression test `test_proUserWithNoPriorImpression_neverSeesUpsell`. `swift test`
  **949 → 955**; xcodebuild + guardrail green.
- **Phase 1 — reprice to the coaching tier (shipped 2026-07-13).** Decision D1.
  New `CadenceCore/PricingPolicy.swift` holds `lifetimeFullPrice = 149.99` and
  `isFoundingPrice(_:)`; `PaywallView.foundingBadge` now calls it (no price literal
  remains in any View). `Cadence.storekit` repriced: annual $34.99→**$79.99** (keeps
  1-month free trial), monthly $4.99→**$12.99**, lifetime $49.99→**$99.99** founding.
  `docs/app-store/metadata.md` and `plans/monetization-plan.md` §2 updated and the
  positioning reversed (value option *within the coaching tier*, not the discount
  tracker). New `PricingPolicyTests` (4). `swift test` **945 → 949**; xcodebuild +
  guardrail green.
- **Phase 0 — docs & positioning (shipped 2026-07-13).** One honest monetization
  story across the repo. Added a **Monetization** section to `CLAUDE.md`; reframed
  `README.md` / `docs/REQUIREMENTS.md` from "free strength coach" to "free tracker +
  paid Coach"; removed stale claims that do not ship (GZCLP, nSuns, HealthKit
  bodyweight, PR timeline, consistency heatmap) from `CLAUDE.md`, `README.md`,
  `docs/REQUIREMENTS.md`, `docs/CITATIONS.md`, and the `williamsLinearPeriodization`
  registry annotation. Reconciled `docs/app-store/release-checklist.md` with
  `metadata.md` (deleted "purchases unlock no features"; added the three Pro IAPs +
  the free/Pro boundary + the App-Review paywall route). Added a GPLv3 **App Store
  exception** to `LICENSE`, referenced from `README.md` and `TRADEMARKS.md`.
  `docs/COMPETITIVE-ANALYSIS.md` present and linked. Docs-only; `swift test` = **945**
  (unchanged), citation integrity green.

## What just shipped — test-pyramid rebuild (2026-07-12)

Plan: `plans/test-pyramid/2026-07-12/`. Moved ~app logic out of SwiftUI Views into a
new headless, `swift test`-able `CadenceFeatures` SwiftPM target, then culled the
unusable 148-test XCUITest suite to a 10-test smoke gate.

- **swift test: 791 → 945**, still headless, still seconds, no simulator.
  New `CadenceFeaturesTests` = **148 tests**; `make test` is the everyday gate.
- **Phase 0** — `CadenceFeatures` + `CadenceFixtures` library targets, `Clock` seam,
  the 15 UI seed builders + `FakeHealthProvider` lifted into `CadenceFixtures`
  (`UITestSeed` is now a thin dispatcher), `Makefile` `test`/`smoke`/`ci`.
- **Phase 1** — pure presenters: `Format`, `AssessmentDisplay`, `HistoryPresenter`,
  `YourWeekPresenter`, `ProgressPresenter`, `WorkoutSummaryPresenter`, `ExportPresenter`.
- **Phase 2** — `@Observable`/model lifts: `IntervalRunner` (+17 moved tests),
  `RestTimerModel` (+6), `ActiveWorkoutModel`, `CardioRecorder` (now protocol-injected),
  `IntervalCueDecider`, `HeartRateParser` (+3), `TrialState`, `AppSettings` (the
  SettingsStore lift). `CadenceTests/` app-hosted tests deleted (moved to swift test).
- **Phase 3** — `HomeCoachModel` incl. **`CoachSignature`** (the coach-cache
  invalidation key — the highest-value test in the plan), `SessionViewModel`,
  `EditablePlan`. Logic extracted + tested; the view *files* still carry SwiftUI markup
  (see guardrail ratchet below).
- **Phase 4** — `CoachRouter` (strength rec → editor, never a recorder — one-line
  assertion over every `CoachSession`), `OnboardingModel` state machine.
- **Phase 5** — 36 UI-test files (148 tests) → **10 smoke tests**; `Cadence.xctestplan`
  drops 3× retry-on-failure + adds a 60s fail-fast allowance; helper timeouts cut
  (waitTap 25→5s); animations disabled under `-uiTest`; screenshots tool split to
  `Screenshots.xctestplan`. A serial, zero-retry run did **8/10 green in 233s (<5 min)**;
  the 2 initial misses were loosened and `SmokeHealthTests` re-verified green — remaining
  reruns blocked only by a degraded CoreSimulator (known env fault per CLAUDE.md).
- **Phase 6** — `scripts/check-test-pyramid.sh` (CadenceFeatures import ban; ≤12 UI
  tests; 400-LOC Features budget with a **shrink-only ratchet** grandfathering the 6
  pre-existing large views) wired into CI; new `ui-smoke` CI job; CLAUDE.md convention.

**Known debt (tracked by the ratchet):** SessionView (1745), HomeView (1108),
CoachDecisionCardView (570), ExercisePickerView (532), RecordAssessmentView (439),
YourWeekView (406) still exceed the 400-LOC view budget — their *logic* is already
extracted; only the SwiftUI markup remains to be split into per-section files. The
guardrail lets them only shrink.

## What shipped earlier — Home / Your Plan bug-fix batch (2026-07-12)

Plan: `plans/home-yourplan-fixes/2026-07-12/plan.md`. Phased A→E, one branch/PR each.
CadenceCore **797 tests, 0 failures**; iOS `xcodebuild` BUILD SUCCEEDED. UI-test runs
were blocked by a degraded simulator (ballooning launches / `server died`); `swift test`
is the reliable gate per CLAUDE.md. Phase-B UI tests (rest-timer + tap-to-open) did pass
before the simulator degraded.

- **Fix 1 (phase A) — "What you did" uses the workout's date.** `CoachDecisionEngine`
  now formats the last-strength / last-cardio relative time and `occurredAt` sort key
  from the event's `start` (`session.date`), not `end` (`endedAt`/finalize time). +1 test.
- **Fix 5 (phase A) — "This Week" refreshes after a date edit.** Editing a past
  workout's date in `SessionView` posts `.workoutHistoryChanged`; `HomeView` observes it
  and bumps `historyRefreshToken` (the `CoachSignature` keys on counts + token, not
  per-session dates), so the strip recomputes without relaunch.
- **Fix 2 (phase B) — edit-mode rest timer suppressed.** The rest timer now starts only
  for the *live* active session (`active.strengthSession?.id == session.id`), so
  editing/correcting a past workout never fires a countdown. +1 XCUITest.
- **Fix 3 (phase B) — tap "What you did" opens the workout.** Added additive
  `ObservedFact.sourceId`; `CoachDecisionEngine` threads the source workout id onto the
  last-strength/last-cardio facts. `HomeView` resolves it to the live
  `WorkoutSession`/`CardioWorkout` and pushes the existing detail destination; the whole
  row is a `Button` + `.contentShape` with a chevron. +1 core test, +1 XCUITest.
- **Fix 4 (phase C) — SKIPPED (user decision).** The plan's `imageInsets` tab-bar nudge
  reproducibly breaks the tab bar's accessibility tree (fails the existing
  `testTabItemsAndSettingsGearHittable` + a VoiceOver/NFR-2 regression). The safe
  `titlePositionAdjustment` alternative only moves the label, not the icon. User chose to
  skip the fix entirely; `RootTabView` is unchanged.
- **Fix 8 (phase D) — cardio HR-zone stacked bar + zone-training citation.**
  `YourWeekView` renders weekly time-in-zone as a horizontal stacked colored bar
  (Z1→Z5, blue→red) above the per-zone legend (with color swatches), reading the existing
  `CardioZoneAggregator` `[Int: Double]`. VoiceOver reads each zone's minutes + % (NFR-2).
  Swapped the science link from `tanakaMaxHR2001` to a **new** `seilerPolarized2010`
  (Seiler 2010, intensity distribution) — added to `CitationRegistry` (`all` +
  `usageReasons`, `CitationIntegrityTests` green) and `docs/CITATIONS.md`. +1 XCUITest.
- **Fixes 6 + 7 (phase E) — planned exercise list + split-frequency inference.**
  - **Fix 6:** additive `PlannedSession.exercises` + `.focus`. `WeeklyPlan.generate`
    populates a concrete prescription per planned strength day via the new reusable
    `CoachSession.strengthExercises(facts:patterns:)` (prefers the user's actual lifts,
    carries goal rep ladders). `PlannedDayPreviewView` renders the full per-exercise list
    (name · sets×rep-ladder · RIR).
  - **Fix 7:** `WeeklyPlan.generate` computes an **effective strength floor** =
    `min(6, max(schedulePreferences.strengthDaysPerWeek, observed trailing-7-day strength
    days))`, so a 5×/week lifter with a stale preference of 2 gets ~5 planned strength
    days (verified: exactly 5). At floor ≥ 4 it switches to a **split** — rotating
    upper/lower focuses across consecutive days, gated by per-body-part recovery windows
    (`focusRecoveryEligible` → `recovery.byBodyPart`) instead of the blanket "no
    consecutive hard days" rule. Whole-body (< 4) plans keep the original 48h/no-back-to-back
    gate. Split days cite `frequencyMeta` + `ramosCampoSplit2024` +
    `parejaBlancoRecovery2020` in the preview's "The science" (HARD RULE). +6 core tests.
  - **Source-of-truth reconciliation (plan Fix 6 note):** `WeeklyPlan.generate` is the
    single source of truth for the **planned-week preview** (it already drives
    `PlannedDayPreviewView` via `DayOutline.sessions`, is date-anchored, now carries
    per-focus exercises). `CoachPlanOptimizer.optimize` remains scoped to **today's**
    exercise selection + weekly volume-insight routing (`CoachSnapshotBuilder`) and was
    intentionally NOT re-used to populate future days — it isn't day-of-week anchored
    across next week. No behavior change to the optimizer path.

_Prior entry:_
_Last updated: 2026-07-12 — Coach test suite: fix 6 optimizer failures + flaky RecencyTest, gate two-a-days, add CI unit-test job._

## What just shipped — Coach test fixes + CI gate (2026-07-12)

Follow-up to the Phase 1-3 "coach recency + volume-routing" work (343949a). CadenceCore
**789 tests, 0 failures** (green across 3+ consecutive full runs, verifying determinism).

- **Insight triage tests (4 assertions).** Phase 3 split the aggregate volume-shortfall
  insight into `planning.partialResolved` (some gaps closed) and `planning.unresolvedVolume`
  (none closed). Updated `CoachPlanOptimizerTests` to assert on the aggregate *family*
  (new `aggregatePlanningShortfall` helper) instead of the retired single ID.
- **Ad-hoc "today" slot guardrails (source, `CoachPlanOptimizer`).** Phase 3's self-scheduled
  today slot now only fires to close a genuine weekly strength shortfall (`!lowParts.isEmpty`)
  and never manufactures a two-a-day the user disallowed (if today already holds a non-rest
  session and two-a-days are off, defer to the aggregate nag). Updated the two schedule-constraint
  assertions to the intended Phase 3 behavior; added `testAdHocTodaySlotRespectsTwoADayPreference`
  and `testAdHocTodaySlotSkippedWhenNoWeeklyShortfall`.
- **Flaky `RecencyTests.testMostTrainedExercisesRotatesByRecency` (pre-existing).** Root cause:
  test fixtures never passed `completedAt` to `addSet`, so `lastWorkingSetAt` defaulted to real
  wall-clock time — recency was time-of-run dependent and same-family lifts tied on `softPenalty`,
  so the winner depended on randomized Dictionary iteration order. Fix: backdate the fixtures'
  `completedAt`, and make `CoachSession.mostTrainedExercises` deterministic — break `effectiveScore`
  ties by the per-exercise (name-level) recency (new `RecoveryState.softNamePenalty`), then a stable
  alphabetical fallback. This also makes within-family rotation actually work (family penalty alone
  can't distinguish two hinge lifts).
- **CI unit-test gate (`.github/workflows/ios.yml`).** New `core-tests` job runs
  `swift build && swift test` on CadenceCore; the TestFlight `testflight-build` job now `needs`
  it. Previously CI only archived for TestFlight and never ran the package tests, so these unit
  regressions were invisible to CI.

## What just shipped — Coaching & UX fixes (P1–P8, 2026-07-11)

Plan + gap analysis: `plans/coaching-ux-fixes-2026-07-11/`. Eight phases, one PR each,
red-test-first. CadenceCore **770 tests, 0 failures**; iOS **BUILD SUCCEEDED**; CI green.

- **P1 — Goal-specific rep ladders (issue 2).** New pure `RepLadder` generates
  descending pyramids: hypertrophy 12-10-8 / 12-10-8-6, strength 5-5-3 / 5-5-3-3,
  endurance 20-18-16. Threaded through `Recommendation.prescribedSession(goal:)`,
  `CoachSession.buildStrengthExercises`, `CoachPlanOptimizer.copy`, and the plan
  editor. Added additive `RecommendedExercise.repLadder`. (+12 RepLadder, +5 prescription tests.)
- **P2 — Productive-midpoint volume targeting (issue 1).** `VolumeLandmarks.productiveTarget`
  = MEV/MAV midpoint. Optimizer now plans toward productive via a 3-pass reshape
  (MEV coverage → breadth → productive top-up, MRV-bounded), while `unresolvedDeficits`
  are reported against MEV — so a productively-dosed part never both under-doses AND
  nags. (+3 optimizer tests.)
- **P3 — Weekly fitness-test recommendation (issue 11).** Pure
  `CoachTestRecommendationEngine` (≤1/week, never-tested-first then most-stale,
  per-kind snooze, "pick a different" cycling). `CoachTestRecommendationCard` on Home
  (Start test / Pick a different / Not right now) routes into `AssessmentDetailView`
  via `HomeRoute.runAssessment`. Persisted `lastTestRecommendationAt` +
  `testRecommendationSnoozes`, exported additively. (+8 engine, +2 export, +3 XCUITests.)
  Added the two new keys to the UI-test clear list.
- **P4 — Additional strength → Start anyway (issue 3).** Root cause: the addon
  `.hardStrengthWarn` session had no exercises → `EditablePlan.from(coach:)` nil →
  dead-end. Fix: `CoachSession.fullBodyStrengthExercises` populates it (reusing P1
  ladders); `launchDecision` falls back to an empty editor. (+2 core, +1 XCUITest.)
- **P5 — Custom-exercise Reassign confirmation (issue 4).** `.confirmationDialog`
  ("Reassigning to <match>, proceed?") → direct reassign / Pick a different exercise
  (rich `ExercisePickerView`, search + pills, built-ins only) / Cancel. Retired the
  plain list. (+2 XCUITests; WorkoutRepositoryTests unchanged.)
- **P6 — Active-workout polish (issues 9 & 10).** Pure `WorkoutTimersModel`
  (work/rest stopwatch). `WorkoutElapsedHeader` gains a wall clock + Work/Rest
  control; new reusable `WallClockLabel` in all 5 workout headers. Per-exercise info
  button → `ExerciseDetailView`. Inline editor: Cancel → "X"; RPE stepper → numeric
  keypad field. (+6 core, +3 XCUITests.)
- **P7 — Your Plan redesign (issue 7).** Fixed the "Thu" label (completed
  strength+cardio day describes its sessions). TODAY-first section; completed days
  tap → history summary; planned days → read-only `PlannedDayPreviewView` (no Start);
  strength tonnage (unit-aware) + cardio HR-zone breakdown (`CardioZoneAggregator`,
  cited tanakaMaxHR2001). Optional age in onboarding + Coach preferences;
  `AppSettings.userAge` exported. Test-rec card moved below the week strip.
  (+7 core, +1 export, +3 XCUITests.)
- **P8 — Layout (issues 5, 6, 12).** Progress Effort/Frequency cards equal height
  (`equalHeight` on the card builder). Best-effort centering: `UITabBarAppearance`
  + Settings gear in a centered 44×44 frame. (+2 XCUITests.)

### Known pre-existing failures (NOT introduced here — confirmed at pre-P3 commit d64dbfa)
- 3 `P3CoachHomeUITests` (Your Plan `.tap()` navigation) + `FR7 …ElapsedTimer…` fail
  identically before this work (default picker Recents tab / NavigationStack `.tap`
  timing / degraded-simulator launches). The new P7 Your-Plan UI tests reach the
  screen fine via `scrollToHittableAndTap`.

_Prior entry:_
_Last updated: 2026-07-10 — Coach: always offer strength when weekly target not met (recovery override); Custom Exercise list UX cleanup._

## What just shipped — Coach recovery override + Custom Exercise UX

### Coach: strength override when all candidates blocked by recovery
- **Problem:** When a full-body workout covered most body parts, SessionEligibilityPolicy blocked all strength candidates despite the user being behind on their weekly target. Coach fell back to rest, leaving zero scheduling options.
- **Fix:** In `CoachDecisionEngine`, when no candidates are eligible but `strengthNeeded` is true (weekly target not met), the best deferred strength session is promoted as primary with an override warning. The warning explains some muscles are recovering but encourages the user to prioritize exercises that feel recovered.
- Added `strengthOverride` warning with citation for transparency.

### Custom Exercise list UX cleanup
- Removed "Delete & reassign" button from incomplete exercise rows
- Moved "Reassign" button from match-display row to the button row alongside "Define"
- `InsightContentView` now shows a "Fix in Settings" button for `.exerciseDefinition` insights
- Threaded `onFixCustomExercises` through `CoachInsightsView`, `CoachPreviewView`, `CoachPreviewScreen`

## What just shipped — Custom exercise completeness (5 phases)

### Problem
Custom exercises with empty `primaryMuscles` were invisible to the coach's volume accounting, causing phantom deficits and naggy "planned volume needs attention" insights.

### Phase 1 — Category-to-Muscle & Category-to-BodyPart fallback
- Added `BodyPart.parts(forCategory:)`, `defaultMuscles(forCategory:)`, `guessCategory(from:)` — category-to-muscle/bodypart fallback + name-to-category guessing from common fitness naming conventions
- `TrainingFacts.make()`: category fallback when primary muscles are empty but category is known
- `CoachPlanOptimizer.muscleIDs(for:)` and `partsCovered(by:)`: category fallback via exercise name guessing
- `PlanAwareInsightEngine.muscleIDs(for:)`: category fallback
- `WorkoutRepository.findOrCreateExercise`: pre-fill muscles from category when template and caller don't provide them
- Added 3 tests to `BodyPartTests.swift` (partsForCategory, defaultMusclesForCategory, guessCategory)

### Phase 5 — Export/import round-trip for custom exercises
- Added `ExportExercise` struct (v5) — carries all exercise facets for round-trip
- `CadenceExport.currentVersion` bumped to 5, with `exercises: [ExportExercise]` field (defaults to `[]` for v4 backward compat)
- `WorkoutRepository.buildExport()` exports all custom exercises with full facet data
- `WorkoutRepository.merge()` imports custom exercises before resolving session exercises
- Added `testCustomExerciseRoundTrip` and `testV4BackwardCompat` to `DataExportTests.swift`

### Phase 3 — Settings: Custom Exercise List with edit + delete & reassign
- New `CustomExerciseListView.swift` — lists custom exercises with category/bodypart chips, incomplete badge, edit sheet, and delete & reassign flow
- Added `WorkoutRepository.reassignAndDeleteExercise(from:into:)` — reassigns all sets to a built-in exercise and deletes the custom one
- Added `SettingsView` → "Exercises" section with link to Custom Exercises
- Added `testReassignAndDeleteExercise` to `WorkoutRepositoryTests.swift`

### Phase 2 — Exercise picker: match suggestion + creation pills
- Added `bestLibraryMatch` computed property to `ExercisePickerView`
- When search has ≥3 chars, shows "Found a good match" card with "Use this exercise" button
- "Create" button now opens a creation sheet with category picker (auto-guessed from name), showing auto-filled body parts and muscles
- Category change updates pre-selected muscles via `BodyPart.defaultMuscles(forCategory:)`

### Phase 4 — Coach insight: "Custom exercises need muscle definitions"
- Added `exerciseDefinition` case to `InsightKind`
- Added `incompleteCustomExerciseNames` field to `TrainingFacts`
- Added `incompleteCustomExercises` rule to `InsightRule.p3Rules` (priority 35)
- Added `brennanExerciseClassification2025` citation + `exerciseDefinitionPool`
- Added "Fix in Settings" button on `CoachDecisionCardView` when insight kind is `.exerciseDefinition`
- Added `HomeRoute.customExercises` with navigation destination
- Added symbol for `exerciseDefinition` insight kind

### Test results
- `swift test`: 724 tests pass (0 failures)
- `xcodebuild`: BUILD SUCCEEDED

## What just shipped — Export freeze fix v3 (root cause: monolithic `Text` layout)

### Problem
Task.detached (v2) moved the *build/encode* off-main but the freeze/watchdog kill
(0x8badf00d) persisted because the **actual** blocker was rendering the entire
multi-MB export payload in a SwiftUI `Text` (`.textSelection(.enabled)`) — a
monolithic CoreText layout on the main thread after `preview = previewText`.
`ShareLink(item: preview)` and the `TextEditor` restore path had the same class
of problem. Simulator tests passed only because seeded data is tiny and the
simulator has no watchdog.

### Fixes
- **No payload string ever touches SwiftUI.** `ExportView` now shows an
  `ExportSummary` card (counts, per-cardio-type breakdown, HR/route sample totals,
  assessment count, date span, preference/coach-profile counts, raw+compressed
  size). `accessibilityIdentifier` retired `export.preview` → `export.summary`.
- **Export writes a file; share is a URL.** The detached task writes
  `Cladiron-Export-<date>.json.gz` (or `.csv`) to the temp dir (clearing stale
  ones) and `ShareLink(item: url)` streams it. Honors `Task.isCancelled` so a
  JSON↔CSV toggle mid-build never runs two builds.
- **gzip compression (`DataCompression.swift`).** First-party zlib deflate via
  Apple's `Compression` framework + a gzip header/CRC32 wrapper (zero deps,
  NFR-6). HR/route-heavy payloads compress ≫5×. `DataExport.encodeJSONGzipped`.
- **Import via `.fileImporter`, off-main, magic-byte sniff.** `DataExport.decodeAny`
  inflates gzip (`1F 8B`) or decodes plain JSON (`{`) — every v1–v4 export stays
  importable forever. Merge runs in a detached task with a fresh `ModelContext`.
- **Compact JSON.** Dropped `.prettyPrinted`; added `.withoutEscapingSlashes`.
- **`merge()` perf.** Name→entity dict caches (was O(sets×exercises)), id-only
  `propertiesToFetch` dedup fetches, and batched saves (~25 cardio / ~50k samples)
  to bound peak memory on large imports.
- **`ExportRoundTripFixture`** (CadenceCore): one seeder covering every cardio
  type, every HIIT preset, all 8 strength structural variations, every assessment
  kind, and full preferences — shared by unit + UI tests.

### Verification
- `swift test`: **697 CadenceCore tests, 0 failures** (+11: compression, summary,
  fixture lossless round-trip, coach determinism at pinned `referenceDate`, scale).
- `xcodebuild`: iOS scheme **BUILD SUCCEEDED**; the 4 `FR6MigrationUITests` export
  cases pass against the new summary card.

_Prior entry:_
_Last updated: 2026-07-09 — Export freeze fix v2: Task.detached replaces @ModelActor._

## What shipped earlier — Export freeze fix v2

### Problem
The previous `@ModelActor ExportActor` approach (2026-07-08) still caused the UI to freeze and crash on large datasets. The `@ModelActor` macro's `DefaultSerialModelExecutor` can run fetches on the main actor's queue, and JSON/CSV encoding ran back on `@MainActor` after the `await` returned. Both contributed to watchdog kills.

### Fixes
- **`Task.detached` replaces `ExportActor`:** `ExportView.rebuild()` now spawns a `Task.detached(priority: .userInitiated)` that creates a fresh `ModelContext` from the `ModelContainer` _inside_ the detached task, runs `buildExport` AND the JSON/CSV encoding — all truly off the main thread. Only final `@State` updates hop back via `MainActor.run`.
- **`ExportActor.swift` deleted:** No longer needed.
- **`weak self` not needed:** `ExportView` is a struct; `@State` uses reference-backed storage so writes from a captured copy still work via `MainActor.run`.

### Verification
- `swift test`: **686 CadenceCore tests, 0 failures** (1 new: `testDetachedExportThenImportThenReExportIsLossless`).
- `xcodebuild`: iOS scheme **BUILD SUCCEEDED**.
- New test validates the exact `Task.detached` + `ModelContext(container)` pattern ExportView now uses.

_Prior entry:_
_Last updated: 2026-07-08 — Gym feedback: Recents tab, machine catalog, per-partner fixes, rep pattern guessing._

## What just shipped — Gym feedback improvements (3 phases)

### Phase 1: Recents tab, machine catalog, equipment-first browsing
- **Recents tab** in `ExercisePickerView`: segmented tabs (Recents / Popular / Browse). Recents shows last ~25 distinct exercises from workout history, sorted by most-recently-used via new `WorkoutRepository.recentlyUsedExercises()`.
- **16 new machine exercises** added to the curated catalog: Machine Fly, Chest-Supported Machine Row, Machine Lat Pulldown, Machine Shoulder Press, Machine Lateral Raise, Machine Reverse Fly, Machine Bicep Curl, Machine Triceps Extension, Seated Dip Machine, Hip Adduction Machine, Hip Abduction Machine, Machine Crunch, plus detailed instructions for all. `seedVersion` bumped from 7 → 8.
- **Equipment-first browsing** in Browse tab: toggle between "By Body Part" (existing chips) and "By Equipment" (equipment chips with body-part sub-filter). `ExerciseFacetIndex` extended with `byEquipment` and `bodyPartsByEquipment` indices.

### Phase 2: Per-partner set copying fix
- **Repeat button** now scopes to the next performer's last set for that exercise, not the absolute last set regardless of who performed it. When solo, falls back to last owner set.
- **`plannedReps`** now accepts a `performerID` parameter so the rep default in the inline editor is performer-aware.

### Phase 3: Pattern-based rep guessing
- **New `RepPattern` engine** in CadenceCore (16 headless tests): detects flat (20-20-20), arithmetic (12-10-8), and prior-session-consensus rep patterns. Runs between the ladder override and last-logged fallback.
- **`WorkoutRepository.repLadderHistory(for:performedBy:excluding:)`** returns `[[Int]]` — one rep array per prior session, oldest-first.
- Wired into `SessionView.plannedReps()` so clicking "Add set" auto-fills the predicted rep count.

### Verification
- `swift test`: **685 CadenceCore tests, 0 failures** (16 new RepPattern tests).
- `xcodebuild`: iOS scheme **BUILD SUCCEEDED**.

_Prior entry:_
_Last updated: 2026-07-08 — Export error handling fix + comprehensive export/import tests._

## What just shipped — Export error handling fix + comprehensive export/import tests

### Bug fix: "No data to export" when data exists
- **Root cause:** `ExportView.rebuild()` used `try?` which silently swallowed ALL errors from `buildExport()` and `encodeJSON()`. Any SwiftData fetch failure, relationship fault, or JSON encoding error set preview to `""` and the UI misleadingly displayed "No data to export." Same pattern in `restore()`.
- **Fix:** Proper `do/catch` with `os.Logger` diagnostic logging. Errors now show `"Export failed: <reason>"` in red. Empty-state detection is now only when `sessions + cardio + assessments` are ALL empty. Merge errors from `restore()` are surfaced instead of defaulting to 0.

### New unit tests (DataExportTests — 11 new, 19 total)
- `testBuildExportEmptyStore` — empty store produces valid export, not throw
- `testBuildExportWithStrengthSessions` — all session metadata fields survive (plan key, template, warm/cool, prescribed load, planned names/ladder, notes, RPE, warmup flag)
- `testBuildExportWithCardioIncludesHRSamples` — cardio with HR + route samples + laps + targets + customTitle survive round-trip
- `testBuildExportWithAssessments` — e1RM + pushupMax assessments with all input fields survive
- `testBuildExportWithPreferencesRoundTrip` — full preferences (unit, PR rule, formula, step goal, warmup/cooldown, schedule prefs, learned coach profile with aerobic + strength + avoidedTags, favorite routines)
- `testFullRoundTripReExportMatches` — export A → JSON → decode → merge → re-export B → sessions/cardio/assessments match by ID
- `testEmptyExportEncodesToValidJSON` — empty CadenceExport produces valid parseable JSON
- `testMergeDoesNotLoseSessionMetadata` — all 14 session-level fields survive merge (plan key, template, warm/cool, prescribed load, partners, notes, isLogged, rep ladder)

### New e2e UI tests (FR6MigrationUITests — +4 new, 6 total)
- `testExportShowsActualDataWhenHistorySeeded` — with "history" seed, preview is NOT "No data to export" and contains `"sessions"`
- `testExportShowsEmptyStateWhenNoData` — with no seed, empty-state message appears
- `testCSVFormatShowsDataRows` — CSV format with history seed contains "Bench Press" data rows
- `testExportIncludesBothStrengthAndCardioWhenMixedSeeded` — mixed seed export contains both `"sessions"` and `"cardio"` keys

### Verification
- `swift test`: **670 CadenceCore tests, 0 failures**.
- `xcodebuild`: iOS scheme **BUILD SUCCEEDED**.

_Prior entry:_
_Last updated: 2026-07-07 — Coach bibliography + four unused-citation integrations._

## What just shipped — Bibliography + unused-citation integration

Plan: `.opencode/plans/bibliography-and-unused-citations-2026-07-07.md`.

### Bibliography in Coach Research Updates
- **`CitationRegistry.usageReasons`** — 47-entry `[String: String]` mapping every
  citation id to a one-line "why the Coach uses it." 1:1 with `all` (test-enforced);
  the `Citation` model stays a pure reference record. `usageReason(forId:)` accessor.
- **`CitationRegistry.bibliography`** — computed, sorted by first-author surname
  (`authors.localizedCaseInsensitiveCompare`).
- **`CoachResearchUpdatesView`** gains a `Section("Bibliography")` below the changelog.
  New private `BibliographyRow` → `CitationDetailView(context: usageReason)` (full
  title/authors/source + "How this applies" + "Read the paper" link).
- **`coach-kb-version.json`** bumped to **v2026.4.0** with a bibliography changelog entry.

### Four unused citations integrated
- **`hiitVo2max`** → added to `vo2TrainingPool` + the VO₂-interval candidate's `citationIds`.
- **`ramosCampoSplit2024`** → new `EvidenceClaimCategory.sessionStructure` +
  `sessionStructurePool`. `CoachPlanOptimizer.classifyStructure`/`sessionStructureFact`
  classify a strength session (full-body / upper / lower / focused) and emit a cited
  `ObservedFact` (new `.sessionStructure` kind + additive `citationIds` on `ObservedFact`).
  `CoachDecisionEngine` attaches it for the primary strength session; `CoachDecisionCardView`
  renders the "open-door" explanation with a `CitationLink`.
- **`drewFinchInjury2016`** → added to `recoveryMonitoringPool`, the consecutive-hard-day
  warning (`CoachDecision`), and the add-on hard-streak warning (`CoachAddOnEngine`).
- **`lauersenInjuryPrevention2014`** → new standalone `injuryPreventionPool` (not tied to any
  claim category) + a "Safety-first guardrails" row in `CoachAboutView` "How it decides,"
  citing it. Still guarded OUT of every flexibility/ROM claim (existing test preserved).

### Tests + verification
- **+7 CadenceCore tests**: `testEveryUsageReasonResolves`, `testBibliographySortedByAuthor`
  (CitationIntegrity); `testNewKBEntryLoads` (KB); `testHIITVo2maxInVo2Pool`,
  `testDrewFinchInRecoveryPool`, `testLauersenInInjuryPreventionPoolNotFlexibility`
  (RecommendationEngine); `testSessionStructureFactSurfaced` (CoachPlanOptimizer).
  Existing `testFlexibilityRuleUsesROMCitationAndNoInjuryPreventionOverclaim` preserved.
- **`docs/CITATIONS.md`** synced: claim-class table (vo2Training, recoveryMonitoring, new
  sessionStructure row), per-entry "Used by" updates, and the "Where these are surfaced" section.
- **Schema safety:** all changes additive (`ObservedFact.citationIds` defaults `[]`, new enum
  cases only). **Full suite: 661 CadenceCore tests, 0 failures. iOS `xcodebuild` BUILD SUCCEEDED.**

_Prior entry:_
_Last updated: 2026-07-07 — Coach preferences reset hotfix + contradictory insight fix + Home redesign._

## What just shipped — Coach preferences hotfix + insight fix + Home redesign

### Part A: Coach preferences reset hotfix
- **Root cause:** Commit `a63e467` added non-optional `excludedCoverageParts: Set<BodyPart>` to the
  `Codable` struct `CoachSchedulePreferences`. Swift's synthesized `Decodable` throws
  `keyNotFound` on missing keys, ignoring `init(...)` defaults. The load site
  (`AppSettings.swift:82-87`) wrapped the decode in `try?` and fell back to `.default`,
  silently wiping all user prefs. Same trap existed for `dailyStepTarget` and
  `CoachPreferenceProfile`.
- **Fix:** Hand-written `init(from decoder:)` + `CodingKeys` on both `CoachSchedulePreferences`
  and `CoachPreferenceProfile` using `decodeIfPresent(...) ?? <default>` for every field.
  Keeps synthesized `Encodable`. Clamping still applies through the decoder.
- **Recovery bonus:** The original (un-reset) blob is still on disk for users who
  haven't re-saved since updating. The lenient decoder restores their real settings on
  next launch.

### Part C: Contradictory "projected low … target met" insight fixed
- **Root cause:** `PlanAwareInsightEngine` early-week branch emitted
  `projectedLowVolumeInsight` for parts with 0 completed + N planned sets without
  checking projected zone. When the plan covered MEV (e.g. Abs 0+6=6 ≥ MEV 6),
  `Format.progress` rendered "target met" under a "projected low" title.
- **Fix:** Compute `projectedZone` in the early-week branch and `guard projectedZone ==
  .belowMEV else { return nil }`, mirroring the normal branch's guard.

### Part B: Home + plan redesign
- **Week strip on Home:** New `WeekStripView` (Features/Coach/) renders Mon–Sun rail
  with status glyphs (green check=completed, ring=today, tint outline=future,
  muted dot=rest) + progress line "N/M strength · N/M cardio this week." Replaces the
  dual "Planned (rest of week)"/"Planned (next week)" section. Tap → Your Plan.
- **Your Week rebuilt:** `YourWeekView` now shows full current week day rows (past→
  today→future continuum with completed/past rendering on `CoachPlanDayRow`), then
  progress bars, then next week preview, then VO₂max. Removed inline goal/experience/
  step-target/schedule settings; replaced with "Coach preferences" link.
- **Dedicated Coach & Plan screen:** `CoachSchedulePreferencesView` absorbs goal,
  experience, and daily step target alongside existing schedule controls. Reachable
  from Home coach card (gear button), Your Plan link, AND Settings → Coach section
  (new "Coach & Plan" row appended at bottom per `settings-append-convention`).
- **UI test updates:** `HomeSimplificationUITests` + `P3CoachHomeUITests` updated for
  new/removed identifiers (`home.plannedRestOfWeek` → `home.weekStrip`, Coach & Plan
  navigation title, goal/experience moved to Coach & Plan).

**Files changed:**
- CadenceCore: `CoachSchedulePreferences.swift` (defensive `init(from:)`),
  `CoachPreferenceProfile.swift` (defensive `init(from:)`),
  `PlanAwareInsightEngine.swift` (early-week zone guard)
- CadenceCore Tests: new `CoachSchedulePreferencesCodableTests.swift` (7 tests),
  new `PlanAwareInsightEngineTests.swift` (5 tests), extended `DataExportTests.swift`
  (+1 legacy schedulePrefs test)
- App: `HomeView.swift` (weekStripSection replaces plannedRestOfWeekSection, route
  wiring), `WeekStripView.swift` (new), `YourWeekView.swift` (rebuild with week
  timeline, CoachPlanDayRow past/completed state), `CoachSchedulePreferencesView.swift`
  (goal/experience/step target), `SettingsView.swift` (+Coach & Plan link)
- UI tests: `HomeSimplificationUITests.swift`, `P3CoachHomeUITests.swift`

**Tests:** 654 CadenceCore, 0 failures. iOS build SUCCEEDED.

_Prior entry:_
_Last updated: 2026-07-07 — Coach whole-body weekly coverage fix._

## What just shipped — Coach "nags about parts it never plans" bug fixed

- **Bug:** With 3 strength + 6 cardio days, a user following the coach's Monday
  workout (4 compounds: squat/bench/row/OHP) got "Abs volume is low: 0/6" and
  "Calves volume is low: 0/6" on Tuesday — for muscles the coach never programmed.
- **Root cause (3-part):**
  1. `CoachPlanOptimizer.lowVolumeAttentionParts` (now `weeklyCoverageParts`)
     excluded 0-set body parts from planning with a `>0` gate.
  2. `InsightRule.volumeVsLandmarks` still emitted `.attention` "low" for every
     0-set part.
  3. `PlanAwareInsightEngine.run` only suppressed 0-set alerts when other
     unresolved deficits existed — when the plan cleanly covered trained parts,
     the raw abs/calves alerts passed straight through.
- **Fix (5 phases, additive schema only):**
  - **Phase 1:** Rewrote `lowVolumeAttentionParts` → `weeklyCoverageParts` —
    returns every `BodyPart` below MEV (no `>0` gate). The optimizer now plans
    whole-body coverage for all 8 parts.
  - **Phase 2:** Bumped `.safe` caps from 5→6 exercises, 16→18 sets/session
    so isolation fits alongside compounds.
  - **Phase 3:** Added `.core` (Plank) and `.locomotion` (Standing Calf Raise)
    to `CoachSession.buildStrengthExercises` with 2-set isolation; raised the
    pattern cap from 4→6. Carries `citationIds` per HARD RULE.
  - **Phase 4:** Fixed the raw-insight leak at `PlanAwareInsightEngine:113` —
    parts with 0 completed + 0 planned sets no longer emit per-part "low" nags.
    Added early-week proration (`elapsed < 3`) so Tuesday morning doesn't show
    "everything reads low." Suppressed nags rely on the `planning.unresolvedVolume`
    aggregate for genuine capacity shortfalls.
  - **Phase 5:** Added even per-slot split allocation (ceil deficit ÷ remaining
    slots) so isolation spreads evenly across strength days. Added additive
    `excludedCoverageParts: Set<BodyPart>` opt-out on `CoachSchedulePreferences`
    (default `[]`, Codable-safe via `BodyPart: Codable`).
- **Schema safety:** All changes additive/defaulted. `BodyPart` gained `Codable`
  conformance (String-backed enum, auto-synthesized). No SwiftData migrations.
- **Tests:** +8 new (Phase 0 repro + E2E). Re-baselined 4 existing tests that
  asserted old per-exercise deficit behavior. Full suite **641 tests, 0 failures**
  (the 2 prior `CoachSnapshotBuilderTests` failures were a test date-boundary bug,
  not SwiftData — `Date()` on Mon/Tue pushed sessions into the prior training week;
  fixed by pinning `testNow` to Thursday).
- **Cited science:** All coaching outputs reuse `CitationRegistry.volumeDoseResponse`;
  new isolation candidates carry `citationIds`. `CitationIntegrityTests` green.

_Files changed_: `CoachPlanOptimizer.swift` (rewrote `lowVolumeAttentionParts` → `weeklyCoverageParts`,
bumped `.safe` caps, even-split allocation), `PlanAwareInsightEngine.swift` (raw-insight leak fix,
early-week proration), `CoachSession.swift` (core+calf isolation in `buildStrengthExercises`),
`CoachSchedulePreferences.swift` (additive `excludedCoverageParts`), `BodyPart.swift` (`Codable`),
`InsightRule.swift` (no change — existing rule correctly flags untrained parts),
`CoachPlanOptimizerTests.swift` (+repro test, re-baselined 3), `CoachSnapshotBuilderTests.swift`
(+E2E test), `InsightEngineTests.swift` (re-baselined 1).

_Prior entry:_
_Last updated: 2026-07-07 — HIIT HR monitoring, round display, skip confirmations._


## What just shipped — HIIT UX fixes (HR monitoring, round display, skip confirmations)

### Fix #1: HR monitoring now works for HIIT workouts
- **Bug:** Interval workouts (HIIT/boxing) bypassed the HR gate entirely. The
  `IntervalSetupView` flow set `intervalLaunch` directly, never routing through
  `begin()` / `hrGateKind` / `PreWorkoutHRView`. Even though the setup sheet saved
  `useHRMonitoring` to settings, the `captureHR` flag on `IntervalView` was always
  `false` (stale `@State` on HomeView).
- **Fix:** Added `captureHR` to `IntervalLaunch` struct. HomeView now reads
  `settings.useHRMonitoring` (updated by the setup sheet's `saveAndStart()`) and
  routes through the HR gate when monitoring is on and no strap is connected.
  `PendingWorkout.Kind.cardioType` now returns `l.saveType` for `.interval` cases.
  `proceedFromHRGate` skips the get-ready countdown for intervals. The fullScreenCover
  uses `$0.captureHR` instead of the ambient `captureHR` state.
- **Always show live HR when available:** Removed `captureHR` guard from the live
  BPM label and HR sampling in `IntervalView` — if a strap is connected (even paired
  in Settings without "Use HR monitoring" toggled), live BPM is displayed and sampled.

### Fix #2: Round number displayed during rest/recovery phases
- **Bug:** Phase labels in `IntervalPlan.swift` factories included round info only
  on work phases (`"Work · Round 3/8"`). Rest phases just said `"Rest"` or `"Recover"`
  — the user couldn't tell which round they were on during recovery.
- **Fix:** Updated all rest phase labels across 6 factory methods + 1 helper in
  `IntervalPlan.swift` to include the round number: `"Rest · Round 3/8"`, `"Recover · 3/4"`, etc.
  Affected: `tabata`, `norwegian4x4`, `gibala` (via `rounded`), `sit` (via `rounded`),
  `rehit` (via `rounded`), `custom`, `boxing`.

### Fix #3: Skip buttons now require confirmation
- **Bug:** All 4 skip buttons in workout views executed immediately — an accidental
  tap could skip a phase, rest timer, warm-up/cool-down, or get-ready countdown.
- **Fix:** Added `.confirmationDialog` to each skip button:
  - `IntervalView`: "Skip this phase?" / "This will advance to the next phase."
  - `RestTimer`: "Skip rest?" / "Rest will end immediately."
  - `GuidedPhaseOverlay`: "Skip warm up?" / "Skip cool down?"
  - `PreWorkoutCountdownView`: "Skip countdown?" / "Start workout immediately."
  - Onboarding skip left unchanged (non-destructive).

**Files changed:** 7 files, +56/-17 lines.
**Tests:** Core suite passes (8 pre-existing failures in unrelated CoachPlan suites).
**Build:** `xcodebuild` iOS scheme — BUILD SUCCEEDED.

_Prior entry:_
_Last updated: 2026-07-06 — Phase 1: RPE on completed set rows._

## What just shipped — Boxing UX + Coach cold-start fix (4 fixes)

### Fix #1: Boxing cooldown bell no longer cut off
- **Bug:** The final boxing bell (1.176s opening-closing-bell.mp3) played at workout
  completion was being cut off ~300–800ms in because `finishedSummary` triggered a
  view transition, and `runnerView.onDisappear` called `cues.deactivate()` which
  deactivated the `AVAudioSession` mid-playback.
- **Fix:** Added `try? await Task.sleep(nanoseconds: 1_500_000_000)` in
  `IntervalView.finish()` after `cues.completed()` so the bell fully rings out
  before the view tears down the audio session.

### Fix #2: Boxing history now shows round/timing details
- **Bug:** `CardioDetailView` showed only date, duration, HR, source — no interval
  structure. Boxing workouts store rounds, work/rest timing, warm-up, cooldown in
  `intervalSummary` (JSON on `CardioWorkout.intervalDetailData`) but this was never
  rendered in history.
- **Fix:** Added an "Intervals" section to `CardioDetailView` that displays
  protocol name, completed rounds, work/rest timing, warm-up time, and cool-down
  time when `workout.intervalSummary` is non-nil.

### Fix #3: "Add 1 min" button for warm-up and cool-down
- **Strength warm-up/cool-down (`GuidedPhaseOverlay`):** Added `addTime(seconds:)`
  to `PhaseCountdownClock` (CadenceCore). If the countdown already finished,
  `addTime` restarts it from now with the added seconds. Added a "+1 min" button
  between Pause and Skip on `GuidedPhaseOverlay`.
- **Boxing intervals (`IntervalView`):** Added `phaseExtension` accumulator to
  `IntervalRunner` that extends the current phase's remaining + overall time.
  Added a "+1 min" button next to Skip, visible only during warm-up and cooldown
  phases.

### Fix #4: "Log your first working sets" no longer shows incorrectly at week start
- **Bug:** `TrainingFacts.totalWorkingSets` only counted sets from Monday-to-now
  (this week). On Monday morning, a user who trained heavily last week but hadn't
  yet logged strength today got `totalWorkingSets = 0` → cold-start insight fired
  incorrectly: "Log your first working sets."
- **Fix:** Added `allTimeWorkingSets: Int` to `TrainingFacts` that counts ALL
  working sets across all passed sessions (not week-scoped). The `InsightEngine`
  cold-start gate now checks `allTimeWorkingSets > 0` instead of `totalWorkingSets > 0`.
  `totalWorkingSets` (week-scoped) is preserved for other rules that need it.

**Tests:** +5 CadenceCore (PhaseCountdownClock: `testAddTimeExtendsPhase`,
`testAddTimeRevivesFinishedPhase`; TrainingFacts: `testAllTimeWorkingSetsCountsAllHistory`,
`testStaleSessionsExcludedFromWeeklyWindow` updated with `allTimeWorkingSets` assertion;
InsightEngine: `testColdStartNotTriggeredWhenPastWeekSetsExist`). Suite 629 tests,
10 pre-existing failures (CoachPlanConstraintOverride/Optimizer/SnapshotBuilder —
unrelated). All new tests pass.

_Prior entry:_
_Last updated: 2026-07-05 — Coach copy now shows explicit done-vs-remaining ("5/8 sets · 3 to go") on every countable output._

## What just shipped — Coach "done vs to-go" progress language

- **Feedback:** with coach insights it wasn't clear how much was **done** vs how much
  **remained** to satisfy a recommendation — the user couldn't tell what to do to "fix"
  a request.
- **Fix:** every countable coach output now uses a consistent progress-bar phrasing —
  `done/target unit · N to go` (or `· target met`) — via a new shared
  `Format.progress(done:target:unit:)` helper in CadenceCore. Citations unchanged;
  numbers come from the same `VolumeLandmarks` bands the copy already referenced.
  - **Volume insights** (`InsightRule`): `Chest: 4/8 sets · 4 to go this week`;
    untrained parts read `0/8 sets · 8 to go`; over-volume reads `24/22 sets · 2 over
    the high end`.
  - **Plan-aware insights** (`PlanAwareInsightEngine`): projected-low reads
    `3 done + 2 planned = 5/8 sets · 3 to go`; behind-plan reads `3 done this week,
    2 planned remaining`; unresolved reads `… sets to go`.
  - **Recommendations** (`RecommendationRule.addVolume`, `CoachRuleSupport`
    volume add/trim): lead with the progress bar, then a concrete `Add ~N` / `trim ~N`.
  - **Observed facts** (`CoachDecision`): strength days, mod-eq minutes, steps append
    `· N to go` / `· target met`.
  - **Add-on cardio** (`CoachAddOnEngine`): `60 min to go on this week's aerobic
    target (90/150). Easy movement closes the gap.`
  - **Your Week** (`YourWeekView`): trailing labels show `N to go · target X` instead
    of `(target: X)`.
- **Tests:** updated 2 `InsightEngineTests` assertions to the new wording. Suite **625
  green**; iOS **build succeeds**.

## What just shipped — Coach snapshot cache (performance: instant set logging)

- **Feedback:** tapping the green checkmark to save a set (and adding an exercise)
  stalled 1–2s — "unacceptable, will kill adoption."
- **Root cause:** `HomeView` computed the whole coach pipeline
  (`TrainingFacts.make`/`CoachFacts.make`/plan optimize/insights over ALL history)
  as plain computed properties that ran ~8–10× per SwiftUI body evaluation. A set
  save does a synchronous `context.save()` that mutates the session `@Query`, which
  re-evaluated the still-alive Home view (even under a pushed `SessionView`),
  re-running the entire pipeline synchronously on the main thread.
- **Fix:**
  - New pure `CoachSnapshotBuilder` (CadenceCore) computes facts→decision→plan→
    insights→recommendation→add-on **once** (no redundant recomputation).
  - `HomeView` caches it in `@State` and rebuilds it in a `.task(id: coachSignature)`
    **off** the render/tap path. `coachSignature` is keyed on coarse history counts
    + the refresh token + coach-relevant settings — deliberately NOT per-set churn —
    so logging a set no longer runs the pipeline. The token is bumped on workout
    completion (`active.finishedSummary`) so Home is fresh on return.
  - Removed the now-dead per-property getters + helpers from HomeView.
- **Tests:** +4 CadenceCore (`CoachSnapshotBuilderTests`: cold-start safe+cited,
  facts wired, deterministic, deleted-sessions ignored). Suite 625 green; iOS build
  succeeds; 12/13 P3CoachHome UI tests pass (the 1 failure, a Settings
  experience-picker scroll assertion, is pre-existing — fails identically on the
  prior commit).

## What just shipped — Coach volume insight covers every body part

- **Feedback:** at week's end the coach said "shoulders on track" but was silent on
  biceps — the user couldn't tell if biceps was on track or simply untrained.
- **Root cause:** `InsightRule.volumeVsLandmarks` did `guard sets > 0 else { continue }`
  — any body part with **zero** weekly sets produced no insight at all.
- **Fix:** untrained parts now emit an attention "…volume is low — 0 sets this week"
  insight (cited), so every one of the 8 `BodyPart` cases is reported (on track /
  low / high). The plan-aware engine still suppresses "low" for parts the weekly
  plan covers, so this only nags about genuinely untrained + unplanned parts.
- **Decoupled the optimizer:** `CoachPlanOptimizer.lowVolumeAttentionParts` now
  ignores zero-set parts (guards `weeklySetsByPart > 0`) so surfacing untrained
  parts to the *user* doesn't make the planner chase deficits for never-trained
  muscles — planning behavior is unchanged.
- **Tests:** +3 CadenceCore (`InsightEngineTests`: every part gets an insight;
  untrained part is attention/low with "0 sets"; untrained-but-planned suppressed).
  Suite 621 green; iOS build succeeds.

## What just shipped — Exercise de-duplication (spelling variants) + duplicate pill fix

- **Root cause:** `ExerciseLibrary.starter` merged our curated catalog with the
  free-exercise-db by *exact* lowercased name, so singular/plural & hyphen variants
  escaped dedup — e.g. the empty curated "Handstand Push-Up" stub coexisted with the
  full imported "Handstand Push-Ups". Diagnostic found **14** such duplicate groups.
- **Catalog fix:** added `ExerciseLibrary.dedupKey` (lowercase, hyphen→space,
  punctuation-strip, single trailing-plural fold) and a `collapseVariants` pass that
  keeps the first (curated, canonical name + our facets) entry and backfills its
  instructions/image/level from the dropped twin. 1001 → 987 entries, zero variant
  collisions.
- **Existing-install migration:** `WorkoutRepository.collapseDuplicateBuiltInExercises`
  runs at seed time — collapses already-seeded duplicate built-in rows by `dedupKey`,
  keeps the canonical/richest row, **repoints logged sets** + favorite, deletes the
  loser. Idempotent; never touches custom exercises.
- **Duplicate pills:** the detail view showed "Push" twice because `force` and
  `category` both render "Push"/"Pull". Extracted `ExerciseFacetTagBuilder.tags`
  (pure) that de-dups labels case-insensitively; `ExerciseDetailView` now renders it.
- **Tests:** +13 CadenceCore (`ExerciseLibraryDedupTests`, `ExerciseFacetTagsTests`,
  `ExerciseDedupMigrationTests`). Core suite 618 green; iOS build succeeds.

## What just shipped — App Store polish + exercise-picker equipment sub-filter

**Equipment sub-filter (feedback: hundreds of movements per body part)**
- `ExerciseFacetIndex` (CadenceCore, pure) precomputes `bodyPart → exercises` and
  `bodyPart → equipment[]` once, so the picker's new **second chip row** (equipment
  under the body-part row) is an O(1) lookup, never an O(catalog) scan per render.
- `ExercisePickerView` shows the equipment row only when a body part is selected,
  no search is active, and the part offers >1 equipment type; resets on part change.
- Tests: +9 CadenceCore (`ExerciseFacetIndexTests`); +1 e2e
  (`ExercisePickerUITests.testEquipmentSubFilterNarrowsBodyPartList`). Core suite
  605 green.

**App Store readiness polish (commit 889d894)**
- Fixed the inline set-editor "Bodyweight" toggle wrapping one char per line → "BW"
  with `.fixedSize()`, VoiceOver label preserved.
- Added missing VoiceOver labels (PR trophy, set checkmark, inline delete, performer
  reorder chevrons); ProgressView chart gained a spoken summary + per-lift trend
  labels; weekday buttons announce selected state; coach/column-header Dynamic Type
  scaling; timer/stepper a11y cleanup.
- Location transparency: background GPS is scoped to a live outdoor workout only
  (verified `CardioRecorder.start/end`; added defensive `.onDisappear` stop);
  documented in About → Privacy and Onboarding.

## What just shipped — Coach surface presence system (coach-surface-design.md, amended)

- **`CoachSurfacePresenter` (CadenceCore, pure)** — resolves the Home coach surface:
  `introducing | ambient | insight | hidden | trial | pro`. Entitlement overrides
  all; else hidden → hidden; else protocol-pack-pending or under the 3-impression
  cap → introducing; else insight (observation available) or ambient. +10 unit tests.
- **`CoachRow`** — compact ambient/insight surface placed after the user's own data
  (quick actions + Planned), before What You Did. Shows the continuous observation
  when present; long-press → Hide Coach offers / Learn more.
- **`CoachPreviewScreen`** — the full pitch moved off Home to a pushed screen: promise,
  live "What the Coach noticed" insight, Pro capability rows (single Pro pill), locked
  "What it would do" (redacted prescription), real citation titles, rate-limited
  Unlock CTA, and a Hide Coach offers footer.
- **HomeView** now renders per surface state: full card (pro/trial) or introducing
  card at top; CoachRow below data for ambient/insight; nothing when hidden. Intro
  impressions counter increments on the introducing card.
- **Settings** → "Hide Coach offers" toggle (free only); re-enabling returns to
  introducing. **Programs** → always-present Coach entry row (reachable even when
  hidden). AppSettings adds `coachHidden`, `coachIntroImpressions` (+ UI-test hooks
  `-coachImpressions N`, `-coachHidden`).
- **Tests:** +10 CadenceCore (`CoachSurfacePresenterTests`); +6 e2e
  (`CoachSurfaceUITests`: introducing card, ambient row → preview screen, hidden
  removes Home presence, hidden still reachable via Programs, Programs entry,
  Settings hide toggle). `MonetizationUITests` (4) still green. Full CadenceCore
  suite 596 green; `xcodebuild` iOS build succeeds.
## What just shipped — fixed the bit-rotted coach-home UI tests

Root causes (pre-existing; CI never ran the UI suite so they drifted):
- **Accessibility-identifier propagation:** a container `.accessibilityIdentifier`
  (e.g. `home.plannedRestOfWeek`, `home.whatYouDid`) fell through to every child,
  clobbering `home.yourPlan`/`home.train`. Fixed with
  `.accessibilityElement(children: .contain)` (matching CoachDecisionCardView).
- **`coach.card.completeBanner`** propagated its id to both the icon and the label
  → ambiguous query → `.combine`d into one element.
- **`coachWednesdayComplete` seed** placed events on a fixed weekday, but the coach
  evaluates "today" — rewritten to anchor the completing strength+cardio to `now`,
  so the day is genuinely complete (both-modalities rule) on any run day.
- **Stale assertions updated:** two-a-day now asserts the coach surfaces the
  remaining *cardio* (not the dead-end "Strength is done today") rather than a
  hardcoded modality; complete-banner queried as a status element; the card
  preferences control now opens Your Plan (where coach settings live).
- **Also:** `CoachDecisionCardView.heroTitle` now names the trainable cardio
  follow-up after strength instead of the generic "Strength is done today".
- **Result:** P3CoachHomeUITests (13), HomeSimplificationUITests (5),
  MonetizationUITests (4), CoachSurfaceUITests (6) — all green (28/28).

## What just shipped — Plan constraint-override ("ignore constraints to meet deficits")

- **`PlanningConstraintPolicy`** (`.safe` default, `.meetDeficits` override) threaded
  through `CoachPlanOptimizer`. When a missed day makes weekly volume unreachable
  without violating guardrails, `.meetDeficits` plans through back-to-back days,
  larger sessions, MRV, and rest days to close the deficits. +5 tests; `.safe`
  preserves all prior behavior.

_Prior entry:_
_Last updated: 2026-07-03 — Free Coach card: continuous insights, locked prescription, rate-limited upsell._

## What just shipped — Continuous coach insights, occasional upsell (coach-surface-design amendment)

- **Insights are now continuous and always shown for free users.** The free-tier
  `CoachPreviewView` leads with the coach's live observation ("What the Coach
  noticed") — the same `coachInsights` the Pro coach computes, recomputed every
  day / after every workout via `historyRefreshToken`. No frequency cap, no
  suppression: seeing real, continuously-updated value is the funnel.
- **Only the prescription is paywalled.** A single-lock "What the Coach would do"
  panel shows the prescription headline with the exact action (`Recommendation.action`)
  redacted behind a `PRO` pill; tapping it opens the paywall. This is the line.
- **"Unlock the Coach" is the only rate-limited element.** New pure
  `CadenceCore.CoachUpsellPolicy` (min 14 days between billboard impressions) gates
  the prominent green CTA; `AppSettings.lastCoachUpsellShown` records the cadence,
  stamped once via `onCTADisplayed` (captured into local `@State` so recording it
  can't blink the button out mid-view). Between billboards the locked panel is
  still a discreet, always-available tap-to-convert path.
- **Science links fixed:** the preview's THE SCIENCE section now renders real
  citation titles (from the insight + prescription) via the full `CitationLink`,
  replacing the 3× "The science ›" placeholder.
- **Free `.coach` route** now shows the full live insights list for everyone
  (observations are free), instead of the hard `CoachLockedView`.
- **Tests:** +5 CadenceCore tests (`CoachUpsellPolicyTests`); `swift build`/`swift test`
  green; `xcodebuild` iOS build succeeds; `MonetizationUITests` suite green (free
  preview, paywall open+restore, free-logging-loop regression, Pro card).

_Prior entry:_
_Last updated: 2026-07-01 — Field-test batch: audio mixing, both-modality completion, no imported-workout references, partner-set attribution._

## What just shipped — Field-test fixes (audio, completion, imports, partners)

- **Background music no longer silenced by cues (SHOW STOPPER):** `TonePlayer` no longer uses
  `AVAudioEngine` (whose output unit interrupted background audio even with `.mixWithOthers`).
  It now pre-renders tick/alert tones to in-memory WAV via the new pure `ToneWAV` builder
  (`CadenceCore`) and plays them through `AVAudioPlayer` — matching the bundled bells, which
  always mixed. `CadenceApp.init()` sets `.playback` + `.mixWithOthers` at launch; interval
  spoken cues set `synth.usesApplicationAudioSession = true`. Only `AVAudioPlayer` /
  `AVSpeechSynthesizer` remain (no `AVAudioEngine`). WAV builder unit-tested; mixing verified
  manually on-device.
- **"Today's workouts are completed" when both done:** `computePlanAdherence` now completes the
  day whenever both a strength and an aerobic event were logged today (any duration), regardless
  of the coach's candidate plan (previously a recovery-plan day dropped real work into offPlan and
  showed a strength-only message). `CoachDecisionCardView` renders the generic (nil-kind) complete
  state as "Today's workouts are completed".
- **No more imported-workout references:** removed both "An imported workout may have included
  strength work" deferral messages, the `.unknownImport` recovery gate, and `RecoveryReason.unknownImport`.
  `TrainingEvent.from(cardio:)` always maps to aerobic/intervals. `CoachAboutView` reworded to drop
  "imported HealthKit data". Watch-cardio-only auto-import is unchanged.
- **Partner sets no longer counted as yours:** the "Repeat" set button and the pending planned-row
  chip in `SessionView` now carry the partner-rotation performer (`nextPerson()`) instead of
  defaulting to the owner — the source of the "8 sets of legs" (4 mine + 4 partner) miscount. Core
  counting already filtered `isOwnerSet`; a regression scenario test now locks it.
- **Tests:** +10 CadenceCore tests (both-modality completion ×3, imported-workout ×2, partner
  volume exclusion ×1, ToneWAV ×4). Full suite 547 tests green; `xcodebuild` iOS build succeeds.

## What just shipped — Liquid glass visibility & warm-up shortcut removal

_Prior entry:_
_Last updated: 2026-07-01 — Liquid glass visibility on main tabs, remove redundant warm-up shortcut._

## What just shipped — Liquid glass visibility & warm-up shortcut removal

- **GlassSupport.swift**: increased `cadenceGlassCard` fill opacity (0.025→0.045 untinted, 0.055→0.08 tinted), stroke opacity (0.12→0.18, 0.22→0.28), glass tint (0.35→0.45), added `.shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)` to both iOS 26+ and fallback paths so cards read as floating glass panels.
- **ProgressView.swift**: `card` helper now accepts optional `tint` param; all major cards get explicit tints (blue for strength/intensity/testResults, teal for volume, orange for effort/frequency).
- **TestsView.swift**: added `.listRowBackground(Color.clear)` to all List sections (intro, battery, advanced) so the glass backdrop and baseline card are visible.
- **WeightsStartView.swift**: removed the redundant "Start with Warm-Up" row; footer updated from "…or warm up first." to "…". Warm-up remains intact inside `WorkoutPlanEditor` / pre-workout settings.
- **FR11Feedback4UITests.swift**: `testStartWithWarmUpThenSession` and `testWarmUpPauses` now use `weights.quickStart` + increment the `editor.warmup` stepper to enable warm-up before starting.
- **FR1PartnersUnitsUITests.swift**: `testAddedPartnerAppearsInEditor` now uses `weights.quickStart` instead of removed `weights.warmupStart`.

## What just shipped — App Store positioning pack

- **`docs/app-store/metadata.md`**: canonical App Store positioning, subtitle, promo text,
  description, keyword bank, screenshot storyboard, review notes, privacy answers, and manual
  links. Locked to the launch decisions: science-minded self-coached lifters, App Store v1,
  free with optional one-time tips.
- **`docs/app-store/release-checklist.md`**: code verification, App Store Connect, IAP,
  screenshot, and post-approval checklist for the first public submission.
- **Public copy cleanup:** About and Coach About now describe the coach as a deterministic
  on-device expert/rule system, not a cloud service or black box. Cold-start insight now uses the
  public product name Cladiron instead of the internal codename Cadence.
- **v1 Watch-scope alignment:** pre-workout live-HR copy now references Bluetooth chest straps
  only; Apple Watch remains described only as a HealthKit import source for v1. Deferred live
  Watch HR plumbing remains dormant behind a disabled internal flag.

## What just shipped — Settings & workflow redesign

### Per-workout settings — remember & reuse
- **`WorkoutSettings`** struct (CadenceCore): all per-workout settings (rest timer, auto-rest, countdown, idle auto-end, plate rounding, GPS, auto-pause, interval palette, spoken cues, warm-up, cool-down, HR monitoring).
- **Per-type memory** in `AppSettings`: `lastStrengthSettings`, `lastCardioSettings`, `lastIntervalSettings`. Saved on workout Start, loaded on next setup screen.
- **`WorkoutPlanEditor`**: now shows rest timer, auto-rest, countdown, plate rounding, idle auto-end toggle + timeout, warm-up, cool-down, HR — all pre-populated from last strength settings.
- **`CardioGoalSheet`**: now shows countdown, GPS accuracy, auto-pause, HR — loaded from `lastCardioSettings`.
- **`TimerCardioSetupView`**: now shows countdown + HR — loaded from `lastCardioSettings`.
- **`IntervalSetupView`**: now shows countdown, color-blind palette, spoken cues, HR — loaded from `lastIntervalSettings`.
- **Every workout path now shows settings before starting** — no workout ever starts without a settings screen.

### Coach settings moved to Coach panel on Home
- **`CoachContextSettingsView`** (new): sheet accessible from the gear icon on `CoachDecisionCardView`. Contains Training Goal, Experience Level, Schedule Preferences link, and Daily Step Target stepper.
- **Removed** the Coach section from `SettingsView` — it now lives on the Home coach panel.
- **`HomeView`**: gear button on Coach card now opens `CoachContextSettingsView` sheet instead of navigating to standalone coach preferences.

### Steps moved to "Your Plan" with adjustable target
- **Removed** the `stepHealthSection` from HomeView front page.
- **Added** steps section to `YourWeekView`: 7-day avg, progress bar vs target, today's steps, status badge, citation link — placed right after mod-equivalent minutes.
- **`CoachSchedulePreferences.dailyStepTarget`**: user-adjustable daily step target (2,000–20,000, step 500, default 8,000). Adjustable in `CoachContextSettingsView`.
- **`StepActivitySummary(from:targetDailySteps:)`**: new initializer that computes status against a custom target (floor 4,000 is fixed).

### Planned (next week) when rest of week empty
- **`plannedRestOfWeekSection`** on HomeView: when `restOfWeekDays` is empty, shows `coachPlan.nextWeekDays` with "Planned (next week)" header instead of "No more planned sessions".

### SettingsView simplified
- **Removed sections**: Coach, Workout, Workout Start, Idle Auto-End, Strength (plate rounding), Cardio, Intervals, Goals, Warm-up & Cool-down.
- **Kept sections**: Units & Records, Health & Sensors, Data, Sounds, About, Support.
- Per-workout settings now live on each workout's pre-start screen, remembered per type.

## What just shipped — Settings cleanup, evidence-based steps, fixed rest days

### Settings cleanup
- **Removed** the user-editable `stepGoal` stepper from Settings. Steps are now an evidence-based health signal, not a user setting.
- **Merged** the two separate Apple Health sections into one "Health & Sensors" area: connection/status row, auto-save toggle, and last sync timestamp all in one place.
- **Fixed** idle auto-end grouping: "Auto-end when idle" toggle now precedes the "Auto-end after N min idle" timeout, which is disabled when the toggle is off.
- **Renamed** Data rows: "Import" → "Import Workout Log", "Export" → "Backup & Restore".
- **Reorganized** Settings into clean sections: Coach, Units & Records, Health & Sensors, Data, Workout, Workout start, Idle Auto-End, Strength, Cardio, Intervals, Goals, Warm-up & Cool-down, Sounds, About, Support.
- **Stopped** exporting `stepGoal` in new exports (`exportPreferences()` writes nil). `ExportPreferences.stepGoal` remains optional for decoding older backups.

### Fixed rest days (Coach schedule preferences)
- **Count control**: segmented picker (1 day / 2 days) when fixed rest is selected.
- **Weekday chips**: Sun–Sat buttons; selecting a new day when full replaces the lowest-rawValue selected day.
- **Defaults**: switching from rolling to fixed initializes with Saturday/Sunday (2-day) or Sunday (1-day). Switching from fixed back to rolling uses `everyNDays: 3`.
- **Footer copy**: "Fixed rest days are days the Coach will not schedule workouts. You can still start one manually."
- **Coverage**: `WeeklyPlan.generate` respects fixed rest days via `isRestDay` (already implemented); new tests prevent regression.

### Evidence-based steps health
- **`StepActivitySummary`** model (CadenceCore) with `StepHealthStatus` (low/building/onTrack), derived from `[DayActivity]`.
- **Fixed thresholds**: floor=4,000, target=8,000, weekly target=56,000 — no user setting.
- **`CoachFacts.make(activityTrend:)`** overload that wraps the existing `make` and attaches a `StepActivitySummary`.
- **Observed fact**: `.weeklySteps` fact shows today's steps, 7-day avg, and status with `stepsHealth` citations.
- **Low-step nudge** (`CoachWarning(id: "lowSteps")`) only when 7-day avg is below 4,000. Cites only `stepsHealthPool` (`saintMauriceSteps2020`, `leeAccelerometer2019`). Does not override strength/cardio session selection. Not presented as medical advice.
- **HomeView**: fetches `activityTrend(days: 7)` alongside `todayActivity()`; displays a step health section with today's steps, 7-day avg, status badge, and citation link.

### Tests (24 new, 0 regressions)
- **`StepActivitySummaryTests`** (12 new): threshold categorization, 7-day avg, weekly total, today steps, static constants.
- **CoachFactsTests** (3 new): `make` with/without activityTrend, preserves existing behavior.
- **CoachDecisionEngineTests** (4 new): low-step nudge, no nudge when on track, no fact without trend, nudge doesn't override primary.
- **CoachSchedulePreferencesTests** (4 new): 1-day and 2-day fixed round-trips, `WeeklyPlan` marks fixed rest days, non-fixed days not forced rest.
- **DataExportTests** (1 new): legacy export JSON with `stepGoal` still decodes.
- **Total**: 508 tests, 0 failures, deterministic.

## What just shipped — local-only + lossless portability + coach Sunday fix + accessibility

### Removed iCloud sync (now fully local)
- **`Store.swift`**: dropped `cloudKitContainerID` + the `cloudKitEnabled` branch; `makeModelContainer(inMemory:)` is always local (`.none`). Removed `cloudSyncEnabled` key/default.
- **`AppSettings.swift`**: removed `cloudSyncEnabled`. **`CadenceApp.swift`**: no cloud flag. **`SettingsView`**: removed the iCloud Sync section. **`AboutView`**: copy now emphasizes local + export portability.
- **Entitlements**: removed `aps-environment`. **Info.plist**: removed `remote-notification` background mode (CloudKit push), **added `bluetooth-central`** (chest strap keeps streaming with the screen locked). Removed the obsolete iCloud-sync UI test.
- Docs (README, CLAUDE.md, REQUIREMENTS.md) updated: no cloud sync; portability via JSON export/import.

### Lossless export/import (`CadenceExport` v4)
- **Fixed a real data-loss bug:** `merge` previously **dropped all cardio on import**. Cardio now round-trips (incl. HR + route samples + metadata).
- Added **assessments** export/import (were never exported), full **session/set metadata** (endedAt, isLogged, planKey, templateName, planned names/ladder, warm/cool seconds, prescribedLoad, partners, usesBodyweight), and an **`ExportPreferences`** block (all settings + schedule prefs + the learned `CoachPreferenceProfile`).
- **`AppSettings.exportPreferences()` / `applyImportedPreferences(_:)`** map settings ↔ the DTO; `ExportView` exports + restores them. v1–v3 exports still decode (custom decoder + optional fields).
- Tests: `DataExportTests.testLosslessRoundTripFullData` (export → JSON → fresh-store import → re-export → identical history + cardio + assessments + prefs) and `testMergeIsIdempotent`.

### Coach: weekly strength cap + Sunday bug
- **Root cause fixed:** `WeeklyStats.weekStart` returned *next* Monday on Sundays (Sunday-first calendar) → "this week" counted 0 strength on Sundays → coach recommended more strength. Now uses a Monday-first calendar (correct on Sundays).
- **Cap enforced:** `CoachSession.candidates` now uses the user's `strengthDaysPerWeek` as the floor and gates general/beginner/reduced-load strength on `strengthCapMet`; `buildTodayRecommendations` won't add strength once the weekly target is met (two-a-day can't override it).
- New test `testThreeStrengthThisWeekMeetsTargetNoMoreStrengthOnSundayEvenWithTwoADay`.

### Deterministic tests (13 flakes fixed)
- Production: `TrainingEvent.from` anchors `lastWorkingSetAt` to `max(setTimes, endDate)` (a session can't end before its last set) + the `weekStart` fix above.
- Tests: pinned `testNow` to a fixed Thursday across 4 suites, anchored helper `completedAt`, pinned `Date()` in WeeklyStats/CoachSchedulePreferences. **Suite now 484 tests, 0 failures, deterministic regardless of time of day.**

### Dynamic Type everywhere
- New `scaledSystemFont(_:relativeTo:weight:design:)` (`@ScaledMetric`-backed) replaces all **24** hardcoded `.system(size:)` usages across 14 files (timers, countdowns, clocks, keypad, icons) so they scale with the user's text size.

### Verification
- `swift test`: 484 tests, 0 failures. `xcodebuild` iOS scheme: **BUILD SUCCEEDED**.

## What just shipped — App Store readiness fixes + supporter (tip-jar) flow
## What just shipped — Supporter / contribution flow (StoreKit 2 tip jar)

Ported from the Parso Radio app, adapted to Cladiron's Observation paradigm. Plan +
decisions: `plans/supporter-flow/2026-06-28/`.

- **`CadenceCore/ContributionPromptEngine.swift`** (+ tests): pure "when to prompt" logic.
  Gate = **6 completed workouts** AND ≥2 sessions; snooze 7 days + 5 launches; never when
  opted-out/already-supporter/first-session/once-per-session. 7 tests, fixed `now` (flake-proof).
- **`App/ContributionStore.swift`**: `@Observable @MainActor` StoreKit 2 layer. Consumables
  `guru.parso.cladiron.tip.small/medium/generous`. `everContributed` in UserDefaults; loads
  products, `purchase`, `restore`, `Transaction.updates` listener. Dormant until ASC products exist.
- **`App/ContributionCoordinator.swift`**: `@Observable` lifecycle. Owns its store, counters
  in UserDefaults, `beginSession`, static `recordWorkoutCompleted`, `evaluate`, dismiss/optOut.
- **`Features/Settings/ContributionToast.swift`** + **`ContributionSupportView.swift`**: bottom
  card (Support / Maybe later / Don't ask again) + Support screen ("Support Cladiron", no charity
  line, placeholder when no products, Restore).
- **Wiring:** `CadenceApp` injects the coordinator via `.environment` and calls `beginSession()`.
  Per decision D6 the prompt is **Home-only**: `HomeView` renders the toast + calls `evaluate()`
  on scene-active, both gated by `contributionPromptAllowed` (no active workout / start sequence).
  Engagement counter bumps via `workoutSaved()` on genuine cardio/interval/swim/logged saves
  (NOT HealthKit ingest) and via `active.finishedSummary` for strength.
- **Settings** gains an appended "Support Cladiron" section; **About** copy reworded
  ("optional tip jar … never required"). **`Cadence.storekit`** added for local testing
  (maintainer adds it to the project + Run scheme per `02-manual-steps.md`).
- Verified: `xcodebuild` **BUILD SUCCEEDED**; `swift test` 481 tests (the 7 new engine tests
  pass; the 13 failures are the **pre-existing** date-relative recovery/weekly-stats flakes,
  reproduced identically on a stashed clean tree).

## What just shipped — App Store readiness fixes

- **Privacy manifest** `Cadence/Cadence/PrivacyInfo.xcprivacy` — Data Not Collected + the one
  required-reason API actually used (`UserDefaults`/CA92.1). Auto-included via the Xcode-16
  synchronized group.
- **Device family → iPhone-only** (`TARGETED_DEVICE_FAMILY = 1`, both app configs).
- **Logic bug fixed:** `RecommendationEngine.pickRoutine` no longer indexes a guarded-empty
  array — added `StrengthPresets.fallback`, uses `presets.first`.
- **Persistent medical disclaimer** added to About (onboarding already had one).
- **VoiceOver:** labels on icon-only buttons (SessionView save-health/menu/info/save-set/RPE,
  Onboarding back); 44pt hit target on the exercise menu; accessible summaries on all 4 Swift
  Charts (HR avg/range, assessment trend; strength chart deferred to its text list); decorative
  alternatives icon hidden.
- **README:** states plainly there is **no companion watch app currently** (Watch data imported
  from Health); a watchOS app is only a possible future addition.
- **Audio background mode kept** (per maintainer — used for interval/finish cues over video).
- Still open (not done): App Store Connect listing/screenshots/privacy answers; CloudKit vs
  `remote-notification` entitlement reconciliation; Dynamic Type on hardcoded-size timer screens.

## What just shipped — Coach card cardio alternatives link

- **`CoachDecisionCardView.swift`**: new `onPickAlternative` callback + a "Not feeling it? Pick another" link rendered under the single-CTA Start button. Gated by `showsAlternativesLink` — only shown for cardio prescriptions (`easyAerobic`/`moderateAerobic`/`vo2Intervals`) that have scored `decision.alternatives`. Accessibility id `coach.card.pickAlternative`.
- **`HomeView.swift`**: `showAlternatives` state presents the previously-unwired `CoachAlternativesView` in a sheet (wrapped in a `NavigationStack`). New `chooseAlternative(_:)` records the preference via `settings.recordCoachSelection(_:alternatives:)` (so Coach learns the modality), dismisses the sheet, then defers `launchDecision(_:)` one runloop turn so the chooser finishes dismissing before the cardio setup sheet/cover presents.
- No `CadenceCore` changes — `CoachDecision.alternatives` and the preference-learning hook already existed; `CoachAlternativesView` already renders each option's `CitationLink` (HARD RULE satisfied).
- Verified: `xcodebuild` Cadence scheme **BUILD SUCCEEDED**; `swift test` 474 tests, 0 failures.

## What just shipped — Coach two-a-days + load accounting + set entry UX

### Load Accounting Model (Phase 1-3)
- **`ExerciseTaxonomy.swift`**: new `LoadAccountingMode` enum — `barbell`, `bodyweight`, `dualDumbbell`, `singleDumbbell`, `isolateralDumbbell`.
- **`Models.swift`**: Exercise gains `loadAccountingMode`, `defaultBarWeightKg`, `loadAccountingUserOverride`. SetEntry gains `barWeightKg`, `loadMultiplier`, `loadAccountingMode`, `effectiveLoadKg` computed property, `SetSample.from(_:)` helper.
- **`ExerciseLibrary.swift`**: `makeExercise(from:)` seeds load accounting defaults from equipment/name heuristics.
- **`WorkoutRepository.swift`**: `addSet` snapshots accounting metadata from exercise onto new sets (only when exercise has explicit accounting mode). `sampleHistory`, `currentPR`, `wouldBePR`, `trendSeries`, `prTimeline` all use `effectiveLoadKg`. `findOrCreateExercise` does NOT seed accounting (rely on seed function). `buildExport`/`merge` include accounting metadata.
- **`DataExport.swift`**: Export v3 with `barWeightKg`, `loadMultiplier`, `loadAccountingMode` fields on `ExportSet`.
- **Calculation call sites updated** to use `effectiveLoadKg`: `TrainingFacts.make`, `TrainingEvent.from(session:)`, `StrengthProgress.series`, `WorkoutSummaryData.lines`, `WorkoutSession.totalVolume`, `SessionView.isAllTimePR`.
- Legacy sets (no `loadAccountingMode`) keep `effectiveLoadKg = weight` unchanged.

### Coach Two-a-Days (Phase 4-6)
- **`CoachDecision.swift`**: new `todayPlannedRecommendations: [CoachSession]` field. Gated behind `schedulePreferences.allowsTwoADays`. When enabled, populates both strength and cardio if both are needed. `computePlanAdherence` updated for two-a-day: only `.planComplete` when both types are done. `effectivePrimary` overrides scored primary when the scored primary's kind is already completed.
- **`CoachDecisionCardView.swift`**: new `twoADayStack` shows stacked rows with independent Start buttons when `todayPlannedRecommendations.count > 1`. Each row has icon, title, subtitle, colored Start button.

### Set Entry UX (Phase 7-8)
- **`SessionView.swift`**: `openInlineEditor` now defaults first-set weight from prior session's first working set; subsequent sets default from previous set's weight. New `inlinePriorWeightHint` shows "Previously started this exercise at X" callout. RPE stepper now has explicit "none" state with clear button. Weight info button beside weight field opens context-sensitive sheet (barbell bar weight, dumbbell entry guidance). First-time dumbbell info sheet auto-shows once via `@AppStorage("dumbbellInfoShown")`. Load accounting metadata snapshotted onto new sets via `WorkoutRepository.addSet`.

### Tests (473 total, 0 failures)
- **New `LoadAccountingTests.swift`** (35 tests): accounting defaults, effective load math, snapshot on creation, export/import round-trip, PR/volume uses effective load, optional RPE, prior-set weight defaults.
- **`CoachDecisionEngineTests.swift`**: 5 new two-a-day tests (both recommendations, cardio-only, strength-only, both-complete, off-by-default).

## What just shipped — Coach UI + splash + completed-plan reconciliation

### Splash restoration
- **`SplashView.swift`**: restored grayscale image-backed splash background from git history. Uses `UIImage(named: "splash")` with `.aspectRatio(contentMode: .fill)`, dark overlay (0.45 opacity), white text. Falls back to `Color(.systemGray6)` if image missing.
- **`splash.jpg`**: regenerated with ImageMagick — grayscale, 1320x2868, center-cropped, quality 88. Source: original image from commit `8c5e5f1`. `Resources/splash.jpg` left unchanged.
- App launch screen settings (`INFOPLIST_KEY_UILaunchScreen_Generation = YES`) unchanged.

### Home This week card cleanup
- **`HomeView.swift`**: removed `Details >` button from `thisWeekCard` header. Users now reach weekly insights via Coach card's `Your week` link.

### Compact Coach's Insights in Your Week
- **`YourWeekView.swift`**: added `insights: [Insight]` parameter. New `Coach's Insights` section at the bottom (after VO₂max). Uses private `CompactInsightRow` — collapsed by default showing icon, title, severity; expands to show message, detail, and citation link. No detail/citation visible until expansion.
- **`HomeView.swift`**: passes `coachInsights` to `YourWeekView` routing.

### Schedule preferences extraction
- **New `CoachSchedulePreferencesView.swift`**: full schedule controls (strength days, cardio days, rest pattern, two-a-days, cardio timing) in a Form behind `"Coach preferences"` navigation title. All citations preserved.
- **`WhyThisTodayView.swift`**: replaced `myPreferencesSection` (inline pickers/toggles/chips) with compact `preferencesLinkSection` — summary text + `"Review my preferences"` link navigating to `CoachSchedulePreferencesView`.
- **`SettingsView.swift`**: added `NavigationLink` to `CoachSchedulePreferencesView` in Coach section, below Training goal and Experience pickers. Accessibility identifier: `settings.coach.schedulePreferences`.

### Completed-plan state reconciliation (Why This Today)
- **`WhyThisTodayView.swift`**: now accepts `addOnRecommendation: CoachAddOnRecommendation` and `onAddOnTap` callback. Body branches on `isPlanComplete`:
  - **Plan complete**: shows `completedPlanExplanationSection` (Plan followed + description + tomorrow preview) and `optionalAddOnsSection` (add-on options with status colors/buttons). Hides Coach's Pick, ruled-out candidates, and why-won sections.
  - **Normal state**: shows Coach's Pick, alternatives, ruled-out, and why-won as before.
- **`HomeView.swift`**: passes `addOnRecommendation` and `handleAddOn` to `WhyThisTodayView`.

### Tests
- All 433 CadenceCore tests pass (0 failures).
- **`P3CoachHomeUITests`**: added `testThisWeekCardDoesNotShowDetailsLink`, `testSettingsLinksToCoachSchedulePreferences`.
- **`WhyThisTodayUITests`**: added `testWhyTodayHidesPreferenceControlsBehindReviewLink`, `testWhyTodayPlanCompleteDoesNotShowCoachPick`.
- Build + test build succeed. UI test suite timed out on simulator (environment limitation) but all code compiles cleanly.

## What just shipped — Coach UI + splash + completed-plan reconciliation

### Splash restoration
- **`SplashView.swift`**: restored grayscale image-backed splash background from git history. Uses `UIImage(named: "splash")` with `.aspectRatio(contentMode: .fill)`, dark overlay (0.45 opacity), white text. Falls back to `Color(.systemGray6)` if image missing.
- **`splash.jpg`**: regenerated with ImageMagick — grayscale, 1320x2868, center-cropped, quality 88. Source: original image from commit `8c5e5f1`. `Resources/splash.jpg` left unchanged.
- App launch screen settings (`INFOPLIST_KEY_UILaunchScreen_Generation = YES`) unchanged.

### Home This week card cleanup
- **`HomeView.swift`**: removed `Details >` button from `thisWeekCard` header. Users now reach weekly insights via Coach card's `Your week` link.

### Compact Coach's Insights in Your Week
- **`YourWeekView.swift`**: added `insights: [Insight]` parameter. New `Coach's Insights` section at the bottom (after VO₂max). Uses private `CompactInsightRow` — collapsed by default showing icon, title, severity; expands to show message, detail, and citation link. No detail/citation visible until expansion.
- **`HomeView.swift`**: passes `coachInsights` to `YourWeekView` routing.

### Schedule preferences extraction
- **New `CoachSchedulePreferencesView.swift`**: full schedule controls (strength days, cardio days, rest pattern, two-a-days, cardio timing) in a Form behind `"Coach preferences"` navigation title. All citations preserved.
- **`WhyThisTodayView.swift`**: replaced `myPreferencesSection` (inline pickers/toggles/chips) with compact `preferencesLinkSection` — summary text + `"Review my preferences"` link navigating to `CoachSchedulePreferencesView`.
- **`SettingsView.swift`**: added `NavigationLink` to `CoachSchedulePreferencesView` in Coach section, below Training goal and Experience pickers. Accessibility identifier: `settings.coach.schedulePreferences`.

### Completed-plan state reconciliation (Why This Today)
- **`WhyThisTodayView.swift`**: now accepts `addOnRecommendation` and `onAddOnTap` callback. Body branches on `isPlanComplete`:
  - **Plan complete**: shows `completedPlanExplanationSection` (Plan followed + description + tomorrow preview) and `optionalAddOnsSection` (add-on options with status colors/buttons). Hides Coach's Pick, ruled-out candidates, and why-won sections.
  - **Normal state**: shows Coach's Pick, alternatives, ruled-out, and why-won as before.
- **`HomeView.swift`**: passes `addOnRecommendation` and `handleAddOn` to `WhyThisTodayView`.

### Tests
- All 433 CadenceCore tests pass (0 failures).
- **`P3CoachHomeUITests`**: added `testThisWeekCardDoesNotShowDetailsLink`, `testSettingsLinksToCoachSchedulePreferences`.
- **`WhyThisTodayUITests`**: added `testWhyTodayHidesPreferenceControlsBehindReviewLink`, `testWhyTodayPlanCompleteDoesNotShowCoachPick`.
- Build + test build succeed.

## What previously shipped — Coach scheduling + audio + add-ons

### Fixed Rest Days
- **`isRestDay(date:restPreference:calendar:)`** in `WeeklyPlan.swift`: `fixed(days:)` short-circuits to `.rest` when the date's weekday is in the configured set; `rolling(everyNDays:)` inserts rest every N days from week start.
- **`futureSessions()`** now accepts `restPreference` and returns `.rest` for fixed rest days before any training check.
- **WhyThisTodayView**: label "Coach will not schedule workouts on selected days." below fixed-day chips.

### Background Interval Audio
- **`audio` added to UIBackgroundModes** in `Info.plist` so cues play when device is locked or app is backgrounded.
- **`WorkoutAudioSession`** switched from `.ambient` to `.playback` with `.mixWithOthers` (no ducking). Added `deactivateSession()` to hand back audio when cues finish.
- **`TonePlayer`** (`Shared/TonePlayer.swift`): `AVAudioEngine`-based sine-wave tone generation replacing `AudioServicesPlaySystemSound` — ticks (1047 Hz, 0.04s) and alerts (1760 Hz, 0.12s) with soft attack/decay envelopes. Shared `countdownStart()` and `rapidEnd()` sequences.
- **`IntervalCues`**: `AudioServicesPlaySystemSound` calls replaced with `TonePlayer.playTick()` / `.playAlert()`. Deactivation now calls `WorkoutAudioSession.deactivateSession()`.
- **`WorkoutCues`**: `SoundBeep` replaced by `TonePlayer`; `AudioToolbox` import removed.
- **`IntervalCueScheduler`** (`Shared/IntervalCueScheduler.swift`): Timer-based cue scheduling (0.5 Hz on `.common` run-loop) decoupled from SwiftUI view ticks. Owned by `IntervalView`; handles 30 s warnings and 3 s countdown ticks.
- **`IntervalView`**: inline cue tracking removed; phase changes reset the scheduler; cleanup on disappear.

### Post-Completion Coach Add-Ons
- **`CoachAddOnRecommendation`** (`CadenceCore/CoachAddOnRecommendation.swift`): `CoachAddOnStatus` (.encouraged, .neutral, .warn), `CoachAddOnOption` (session + status + message + citations), `CoachAddOnRecommendation` (primary option + secondary list).
- **`CoachAddOnEngine.run()`** (`CadenceCore/CoachAddOnEngine.swift`): evaluates post-completion add-ons — encourages easy cardio when below targets, warns for additional strength/HIIT/boxing after plan complete, warns on poor readiness and hard-day streaks. Copy avoids "overtraining" language.
- **`CoachDecisionCardView`**: now accepts `addOnRecommendation` and `onAddOn` callback. `planComplete` state shows "On plan" banner + primary encouraged CTA ("Add easy cardio") + "Choose extra workout" expandable section with status-colored options (green=encouraged, orange=warn).
- **`HomeView`**: computes `addOnRecommendation` from `CoachAddOnEngine` when `planComplete`; `handleAddOn()` routes `.warn` statuses through a confirmation dialog ("Start anyway" / "Choose easier option").
- **Tests**: all 433 existing CadenceCore tests pass. New types are additive and covered by type system.

## Repo / branch
- Repo: `/Users/arley/github/parso-workout-ios-app`
- **`main`** = current. Builds + tests green.

## Notes / decisions in effect
- All merges to `main` so far were fast-forward; PRs #7–#13.
- Schema changes additive + CloudKit-safe; `[String]` model attrs are delimited-String-backed (`StringArray`).
- `CoachPreferenceProfile` stored as JSON `Data` in UserDefaults under key `settings.coachPreferenceProfile` (not SwiftData).
- `CoachSchedulePreferences` stored as JSON `Data` in UserDefaults under key `settings.coachSchedulePreferences` (same pattern).
- Fixed-day chip UI preserved per plan; behavior fixed first, redesign deferred.
- Background cues now require iOS `audio` background mode + `.playback` category.

## Phase 1: RPE display on completed set rows (2026-07-06)
- Added RPE badge (small rounded number chip) on `completedSetRow` in SessionView.swift
- RPE visible without tapping to edit; appears only for working sets with RPE logged
- Row height unchanged at minHeight: 44

## Phase 2: Remove zombie exercises (2026-07-06)
- Added 27 `curatedAlias` mappings so common curated exercises (Dumbbell Curl, Kettlebell Swing, etc.)
  get enriched with images and instructions from free-exercise-db
- Deleted 60 exercises from the curated catalog that have no free-exercise-db equivalent
  (Banded Chest Press, Bird Dog, Broad Jump, Burpee, Diamond Push-Up, Double-Under, Wall Ball, etc.)
- Users can still find equivalents from free-exercise-db imports (~22k exercises) under different names
- Added `testNoZombieExercisesMissingImageAndInstructions` as permanent regression guard
- Bumped seedVersion to 7; migration deletes stale built-in exercises from existing user stores

## Phase 3: Coach doesn't paint itself into a corner (2026-07-06)
- Added `testMondayPostWorkoutSuppressesUntrainedPartAlertsWhenWeekIsTight` scenario test
- Fixed `PlanAwareInsightEngine` to suppress individual "low volume" attention insights for
  body parts with 0 completed sets when the week's plan already has unresolved deficits
- Also fixed the `plannedStrengthSessionCount == 0` branch to suppress low-volume alerts
  for untrained parts when no remaining slots are available

## Phase 4: Kettlebell load accounting + info treatment (2026-07-06)
- Added `dualKettlebell`, `singleKettlebell`, `isolateralKettlebell` to `LoadAccountingMode` enum
- Kettlebell exercises now get the same load accounting as dumbbells: entered weight = one bell,
  doubled for two-bell exercises, single for swings/snatches/Turkish get-ups
- Added `isSingleKettlebellMovement` name pattern matching (swing, snatch, Turkish get-up, etc.)
- Added kettlebell info popup (`kettlebellInfoShown` via AppStorage), mirroring dumbbell flow
- Updated weight info sheet to show kettlebell-appropriate guidance
- Updated `effectiveLoadKg` and `prospectiveEffectiveLoadKg` for new modes
- Existing kettlebell exercises backfill their accounting mode on next seed pass
- Added 8 kettlebell load accounting tests

## Phase 5: Custom exercise facet editing (2026-07-06)
- Added `CustomExerciseEditView` — a sheet opened from `ExerciseDetailView` when the exercise
  is user-created (`isCustom == true`). Users can tag body regions, specific muscles,
  equipment, category, mechanics, and force
- Added `WorkoutRepository.updateExercise` to persist facet edits on custom exercises
- Added edit banner on `ExerciseDetailView` for custom exercises with an "Edit" button
- Extracted `FlowLayout` to shared `Views/Shared/FlowLayout.swift`
- Made `BodyPart.part(forMuscleID:)` public for use in the edit UI
