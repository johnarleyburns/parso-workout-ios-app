# Coach Recovery-Aware Redesign — Implementation Plan

**Status:** draft · **Date:** 2026-06-22 · **Source:** `COACH_REAL_WORLD_TRAINING_REDESIGN.md`

## Overview

Replace the current `rules → recommendations → sort → top` coach pipeline with a recovery-aware, balanced-training decision engine:

```
unified training events
  → rolling load + recovery + weekly balance facts
  → generate candidate sessions
  → hard eligibility gates
  → score eligible candidates against the adaptive 7-day plan
  → choose today's session
  → explain observed facts, exclusions, choice, and citations
```

The primary regression to prevent: recommending deadlift progression immediately after logging a full-body session containing deadlifts.

---

## 1. Architecture — New Types (all in `CadenceCore`)

### Core domain types

| File | Key types | Purpose |
|------|-----------|---------|
| `TrainingEvent.swift` | `TrainingEvent`, `EventKind`, `StrengthEventDetails`, `AerobicEventDetails`, `EventSource`, `EventCompletion` | Unified value layer over strength + cardio + imported workouts |
| `MovementPattern.swift` | `MovementPattern` (squat, hinge, horizontal push/pull, vertical push/pull, carry, locomotion, core) | Used for pattern-based recovery gates and balance tracking |
| `RecoveryState.swift` | `RecoveryState`, `RecoveryWindow`, `RecoveryReason`, `FactConfidence` | Per-exercise, per-pattern, per-body-part recovery windows |
| `SessionEligibilityPolicy.swift` | `EligibilityDecision`, `DecisionReason`, `DecisionNote` | Hard gates that run before scoring — cannot be overridden by priority |
| `CoachSession.swift` | `CoachSession`, `CoachSessionKind`, `LaunchPayload` | Candidate session types: strength, easy/moderate aerobic, VO2 intervals, recovery, rest, assessment |
| `CoachDecision.swift` | `CoachDecision`, `DeferredCandidate`, `ObservedFact`, `WeeklyBalance` | The final top-level output: primary session, alternatives, deferred, facts, balance, citations |
| `WeeklyPlan.swift` | `WeeklyPlan`, `DayOutline` | Adaptive 7-day rolling outline: hard/easy/rest labels, strength vs aerobic shape |
| `CoachFacts.swift` | `CoachFacts`, `RecoveryState`, balance facts (strength days, pattern coverage, moderate-equivalent minutes, VO2max trend, readiness) | Replaces/extends TrainingFacts with rolling windows; consumes unified events |

### Readiness model

| File | Key types | Purpose |
|------|-----------|---------|
| `ReadinessEntry.swift` (or add to `Models.swift`) | `ReadinessEntry` (@Model) | Optional once-daily: muscle soreness, fatigue, sleep quality, stress (1–5), pain/illness flag |

### HealthKit import fix

| Change | Location | Purpose |
|--------|----------|---------|
| Add `importedWorkoutKindRaw: String?` field | `CardioWorkout` model in `Models.swift` | Preserve HK source type (traditionalStrength, functionalStrength, running, walking, cycling, swimming, rowing, hiit, boxing, other) |
| Add `ImportedWorkoutKind` enum | new in `Services.swift` | Distinguish unknown imported strength from cardio — mapped from `HKWorkoutActivityType` |
| Change `cardioType(from:)` mapping | `HealthKitProvider.swift:253-263` | Stop mapping `traditionalStrength`/`functionalStrength` to `.other`; pass the real type |
| Deduplication by HK UUID | `WorkoutRepository.ingest()` | Skip imported workouts whose UUID matches an app-authored `HKWorkout` writeback |

### Science registry additions

New citation IDs in `CitationRegistry`:
- `acsmResistance2026` — ACSM 2026 position stand
- `whoPhysicalActivity2020` — WHO physical activity guidelines
- `usPhysicalActivity2018` — U.S. guidelines
- `pellandDoseResponse2026` — Pelland et al. dose-response
- `ramosCampoSplit2024` — Ramos-Campo split comparison
- `parejaBlancoRecovery2020` — Pareja-Blanco recovery kinetics
- `sawMonitoring2016` — Saw et al. monitoring
- `meeusenOvertraining2013` — Meeusen et al. overtraining consensus
- `schumannConcurrent2022` — Schumann et al. concurrent training
- `crowleyVO2Intensity2022` — Crowley et al. VO2 intensity
- `poonHIIT2024` — Poon et al. HIIT umbrella review

Update existing `frequencyMeta` copy: volume-equated frequency has no meaningful independent hypertrophy effect.

### Deprecations (keep compiling, phase out)

- `VolumeBands.mev`, `.mav`, `.mrv` naming → `VolumeGuidance` with `startingTargetRange` / `personalBaselineRange`
- `VolumeZone.belowMEV`, `.overMRV` → `belowTarget`, `aboveCeiling` or similar neutral labels
- `estimatedVO2max` taking max across protocols → protocol-specific with trend from same protocol only
- `pickRoutine` from Coach CTA path → removed after Phase 5 UI migration
- `daysSinceLastSession` as sole recovery signal → kept for backward compat, superseded by `RecoveryState`

---

## 2. Data Flow (New Pipeline)

```
HomeView / Coach call-site
  │
  ├─ @Query sessions + @Query cardio + @Query assessments + @Query readiness
  │
  ▼
TrainingEvent.make(from: sessions, cardio, assessments, readiness, now)
  │  adapters convert WorkoutSession → TrainingEvent (strength)
  │  adapters convert CardioWorkout → TrainingEvent (aerobic)
  │  ingested unknown strength → TrainingEvent (unknown)
  │  assessments → TrainingEvent (assessment)
  │
  ▼
CoachFacts.make(from: events, goal, experience, formula, now)
  │  rolling 72h recovery windows
  │  rolling 7d dose
  │  rolling 28d trends
  │  moderate-equivalent minutes
  │  pattern/body-part coverage
  │  readiness flags
  │
  ▼
CoachDecisionEngine.run(facts)
  │  1. generate CandidateSession list
  │  2. SessionEligibilityPolicy.evaluate each candidate
  │  3. filter to .eligible only
  │  4. score eligible against WeeklyPlan
  │  5. select primary + alternatives
  │  6. collect deferred, observedFacts, weeklyBalance
  │
  ▼
CoachDecision → UI layer
  │  CoachCardView(decision:) renders appropriate card state
  │  primary.launchPayload is the CTA target
  │  deferred shown in "Why this today"
```

---

## 3. Phase-by-Phase Implementation

### Phase 1 — Reproduce and Lock the Bug

**Branch:** `phase-1-recovery-regression-tests`  
**Depends on:** `main`

**Files to create:**

1. `CadenceCore/Tests/CadenceCoreTests/CoachRecoveryRegressionTests.swift` — new test file

**Tests to add:**

| Test | What it proves |
|------|---------------|
| `testFullBody42MinAgoBlocksDeadliftProgression` | Log squat+bench+deadlift at `now-42min`; assert current engine's top recommendation is NOT a deadlift progression (this test FAILS on main — that's the point) |
| `testFullBody42MinAgoBlocksSquatProgression` | Same session; assert squat progression is not top |
| `testFullBody42MinAgoBlocksBenchProgression` | Same session; assert bench progression is not top |
| `testDeadlift23h59mAgoBlocksDeadliftProgression` | Deadlift <24h ago → still blocked by exact-lift gate |
| `testDeadlift24h01mAgoButPatternBlocked` | Deadlift >24h but posterior chain <48h → blocked by pattern gate |
| `testCardPayloadMatchesLaunchedPayload` | Verify that `Recommendation.prescribedSession` is what `launchPrescription` actually launches (for current engine) |

**Acceptance criteria:** All tests compile; the first 3 tests FAIL (proving the bug exists). The payload-match test may also fail depending on CTA behavior.

---

### Phase 2 — Event and Fact Layer

**Branch:** `phase-2-events-and-facts`  
**Depends on:** `phase-1-recovery-regression-tests` (stacked)

**New files in `CadenceCore/Sources/CadenceCore/`:**

1. **`MovementPattern.swift`**
   ```swift
   public enum MovementPattern: String, CaseIterable, Sendable {
       case squat, hinge, horizontalPush, horizontalPull, verticalPush, verticalPull, carry, locomotion, core
   }
   ```

2. **`TrainingEvent.swift`** — unified event layer (structs, not @Model)
   - `TrainingEvent` with `id: UUID`, `start`, `end`, `kind: Kind`, `source: EventSource`, `completion: EventCompletion`
   - `EventKind`: `.strength(StrengthEventDetails?)`, `.aerobic(AerobicEventDetails)`, `.intervals(AerobicEventDetails)`, `.unknown`
   - `StrengthEventDetails`: exercise-level data (movement patterns, hard set count, top set, e1RM, RPE, reachedFailure, last working-set time)
   - `AerobicEventDetails`: modality, impact, duration, intensity classification + confidence, moderate-equivalent minutes, lower-body overlap
   - `EventSource`: `.appStrength`, `.appCardio`, `.healthKitImported`, `.assessment`
   - `EventCompletion`: `.completed`, `.inProgress`

3. **Adapters** (extensions or standalone functions):
   - `TrainingEvent.from(session: WorkoutSession)` — converts strength session
   - `TrainingEvent.from(cardio: CardioWorkout)` — converts cardio workout
   - `TrainingEvent.from(assessment: Assessment)` — converts assessment
   - Deduplication: skip imported workouts whose UUID matches app-authored writeback

4. **`CoachFacts.swift`** — replaces aspects of `TrainingFacts` for the new engine
   - `CoachFacts` struct (pure, Sendable)
   - `RecoveryState`, `RecoveryWindow` (by exercise, pattern, body part)
   - `WeeklyBalance`: strength days, pattern coverage, sets (fractional), moderate-equivalent minutes, hard/easy day classification, VO2max trend, readiness, data completeness
   - `CoachFacts.make(from: events, goal, experience, formula, now)` — rolling-window computation
   - Rolling windows: 72h (acute/recovery), 7d (weekly dose), 28d (trend)
   - Moderate-equivalent: `moderateMinutes + 2 * vigorousMinutes`

**Tests to add in `CadenceCore/Tests/CadenceCoreTests/`:**

1. **`TrainingEventTests.swift`**
   - Session → TrainingEvent conversion (sets, reps, patterns, RPE)
   - CardioWorkout → TrainingEvent conversion (duration, type, intensity)
   - Assessment → TrainingEvent conversion
   - In-progress session excluded from completed events, but sets create active hard block

2. **`CoachFactsTests.swift`**
   - Rolling 72h recovery windows: exact timestamps, not calendar boundaries
   - Sunday workout still in facts on Monday (<7d)
   - Events exactly outside 7d drop out
   - `now` injectable in every test
   - Moderate-equivalent: 75 vigorous minutes = 150 moderate-equivalent
   - Missing HR intensity → low-confidence classification, no fabricated precision
   - Pattern coverage tracking
   - In-progress sets block conflicts but don't count as completed weekly dose
   - Same-protocol VO2max values trend; cross-protocol values do not

**Acceptance criteria:**
- `swift test` passes all new tests
- Existing tests in `CadenceCore` still pass (no regressions)
- `CoachFacts` does not break `TrainingFacts` — they coexist

---

### Phase 3 — Eligibility and Decision Engine

**Branch:** `phase-3-eligibility-decision`  
**Depends on:** `phase-2-events-and-facts`

**New files in `CadenceCore/Sources/CadenceCore/`:**

1. **`SessionEligibilityPolicy.swift`**
   - `EligibilityDecision` enum: `.eligible(notes:)`, `.defer(until:reasons:)`, `.blocked(reasons:)`
   - `DecisionReason` struct: `id`, `message`, `citationIds`
   - `DecisionNote` struct: informational annotations
   - `RecoveryReason` enum: exact lift, pattern, body part, unknown import, fatigue, pain
   - `SessionEligibilityPolicy` struct with static `evaluate(_:against:)` → `EligibilityDecision`

   **Hard gates implemented:**
   1. Active workout → defer (show Resume)
   2. Exact lift <24h since last working set → defer
   3. Same hard pattern/body part <48h after hard exposure → defer
   4. High fatigue (≥2 of: failure reported, high set count, RPE≥9, poor readiness, performance decline) → defer 72h
   5. Unknown imported strength <24h → defer hard full-body, allow easy aerobic
   6. Hard lower-body collision: squat/hinge <24h → defer running intervals, sprint, hard cycle; allow walk/easy cycle/swim
   7. Pain/illness concern → block hard training, allow rest/easy
   8. Plan conflict: routine only eligible if every hard main movement is eligible

2. **`CoachSession.swift`**
   - `CoachSession` struct: `id`, `kind`, `title`, `duration`, `exercises`, `modality`, `intensity`, `trainingLoadTags`, `citationIds`, `launchPayload`
   - `CoachSessionKind`: `.strength`, `.easyAerobic`, `.moderateAerobic`, `.vo2Intervals`, `.recovery`, `.rest`, `.assessment`
   - `LaunchPayload`: opaque payload that the CTA launches (strength → `WorkoutPlan` reference, cardio → type+duration, recovery → guided stretching, rest → nothing)
   - Candidate generators: `CoachSession.candidates(for: facts)` → `[CoachSession]`

3. **`CoachDecision.swift`**
   - `CoachDecision` struct: `id`, `generatedAt`, `primary`, `alternatives`, `deferred`, `observedFacts`, `weeklyBalance`, `confidence`, `citationIds`
   - `DeferredCandidate`: session + eligibility decision explaining why
   - `ObservedFact`: timestamped observations used in the decision
   - `CoachDecisionEngine` enum with `run(facts) → CoachDecision`

   **Scoring order (after eligibility filtering):**
   1. Honor active user-selected program's next valid day
   2. Close largest weekly fitness gap (strength coverage vs aerobic minutes)
   3. Preserve hard/easy rhythm and recovery
   4. Progress a lift only when its session is eligible
   5. Prefer adherence, equipment, time, modality preferences
   6. Prefer lower-risk/easier options when confidence is low

4. **`WeeklyPlan.swift`**
   - `WeeklyPlan` struct: rolling 7-day outline, recomputed after every completed/imported workout
   - `DayOutline`: hard/easy/rest label, suggested session shape
   - Template shapes by availability (2/3/4/5+ training days)
   - Beginner full-body A/B replacement for cold-start "squat bench deadlift"
   - Consume actual events and reflow future days

**Tests to add:**

1. **`SessionEligibilityPolicyTests.swift`**
   - Full-body 42min ago → squat/bench/deadlift deferred, easy aerobic eligible
   - Deadlift 23h59m ago → exact deadlift deferred
   - Deadlift 24h01m ago but posterior chain hard <48h → still deferred by pattern
   - Low-volume technique work at low RPE + good readiness → non-hard technique candidate eligible
   - Failure + high RPE + poor readiness → 72h conservative window
   - Upper-body strength yesterday → easy run eligible; hard full-body containing bench blocked
   - Lower-body strength today → sprint/HIIT deferred; easy walk/cycle eligible
   - Unknown imported HK strength today → hard full-body deferred, easy aerobic eligible
   - Pain/illness concern → hard candidates blocked; no diagnosis text
   - All gates documented and inspectable

2. **`CoachDecisionEngineTests.swift`**
   - Two strength days, zero aerobic → moderate aerobic outranks strength progression
   - Zero strength days, 150 aerobic minutes, muscles eligible → strength wins
   - Active program honored first
   - Beginner with no cardio history → moderate session, not SIT or 4×4
   - Card payload matches launched payload
   - Deleting/restoring a workout recomputes the decision
   - Decision is deterministic given same inputs

3. **`WeeklyPlanTests.swift`**
   - Beginner gets alternating full-body A/B (squat/bench/row, hinge/press/pull)
   - A/B does not contain 3-set squat+bench+deadlift
   - 2-day template has ≥48h between hard full-body sessions
   - Off-plan workout consumed and future days reflow
   - Aerobic work not silently displaced at 4+ strength days

**Acceptance criteria:**
- `swift test` passes new tests
- Phase 1 regression tests now PASS (bug fixed)
- Old `RecommendationEngine` still works (behind adapter until Phase 5 migration)
- No `pickRoutine` calls from Coach CTA path

---

### Phase 4 — HealthKit Integrity

**Branch:** `phase-4-healthkit-integrity`  
**Depends on:** `phase-3-eligibility-decision`

**Changes:**

1. **`Models.swift`** — Add to `CardioWorkout`:
   ```swift
   var importedWorkoutKindRaw: String? // stores ImportedWorkoutKind.rawValue, safely migratable
   ```
   Computed property:
   ```swift
   var importedWorkoutKind: ImportedWorkoutKind? {
       get { importedWorkoutKindRaw.flatMap(ImportedWorkoutKind.init(rawValue:)) }
       set { importedWorkoutKindRaw = newValue?.rawValue }
   }
   ```

2. **`Services.swift`** — Add enum:
   ```swift
   public enum ImportedWorkoutKind: String, Sendable, CaseIterable {
       case traditionalStrength, functionalStrength
       case running, walking, cycling, swimming, rowing
       case hiit, boxing
       case other
   }
   ```
   Add `importedKind: ImportedWorkoutKind?` to `IngestedWorkout`.

3. **`HealthKitProvider.swift`** — New mapping function:
   ```swift
   static func importedWorkoutKind(from type: HKWorkoutActivityType) -> ImportedWorkoutKind
   ```
   Key: `.traditionalStrengthTraining` → `.traditionalStrength`, `.functionalStrengthTraining` → `.functionalStrength`. Stop mapping these to `.other` cardio type. Set `IngestedWorkout.type = .other` for unknown/strength but set `importedKind` correctly.

4. **`WorkoutRepository.swift`** — In `ingest()`:
   - Store `importedKind` on the `CardioWorkout` model
   - Deduplicate: if the HK UUID matches an app-authored strength summary UUID (written via `saveStrengthWorkout`), skip the row entirely
   - Imported unknown strength without movements: contributes one strength day, duration, session timing, 24h conservative block, but NO fabricated per-muscle set counts

5. **Backfill** — A one-time migration function (called on first launch after upgrade) that:
   - Finds existing `.other` CardioWorkout rows
   - If the source HealthKit metadata makes classification certain, backfills `importedWorkoutKind`
   - Otherwise retains unknown

**Tests to add in `CadenceCore/Tests/CadenceCoreTests/`:**

- **`ImportedWorkoutKindTests.swift`**
  - Traditional strength import preserves kind, not mapped to cardio `.other`
  - Functional strength import preserves kind
  - Deduplication by HK UUID works
  - Unknown strength contributes 24h block but no fabricated sets
  - Running/cycling/swimming mapped correctly

**Acceptance criteria:**
- `swift test` passes
- Imported HK strength shows as strength in the event layer
- No double-counting of app-authored writebacks

---

### Phase 5 — UI Migration

**Branch:** `phase-5-ui-migration`  
**Depends on:** `phase-3-eligibility-decision` (can stack on Phase 3; Phase 4 can merge independently)

**Files to modify/create in `Cadence/Cadence/`:**

1. **`Features/Home/HomeView.swift`**
   - Replace `coachRecommendation: Recommendation` with `coachDecision: CoachDecision`
   - Compute `CoachFacts` from unified events (sessions + cardio + assessments + readiness)
   - Pass `CoachDecision` to the card
   - Replace `launchPrescription(_:)` with `launchDecision(_:)` — launches `primary.launchPayload` directly
   - Remove `pickRoutine` from the Coach CTA path
   - Add `@Query` for `ReadinessEntry` model
   - `syncCardioFromHealth()` now feeds into unified events properly

2. **`Features/Coach/CoachCardView.swift`** — Full rewrite:
   - Accepts `CoachDecision` instead of `Recommendation`
   - **5 explicit card states:**
     1. **Train** — eligible strength or hard cardio; green "Start <session>" CTA
     2. **Easy aerobic** — behind aerobic target with recovery constraints; teal "Start easy cardio" CTA
     3. **Recovery** — no useful hard session eligible; amber "Start recovery" + secondary "Take a rest day"
     4. **Rest/safety** — pain/illness or very poor readiness; NO green CTA, safety copy only
     5. **Resume** — active workout supersedes; "Resume workout" CTA
   - Each state shows: eyebrow (COACH · RECOVERY etc.), headline, recent event, recovery chips or session prescription, next hard eligibility time, weekly balance context, "Why this today" link
   - Accessibility: `coach.card.state`, `.recentEvent`, `.nextEligible`, `.weeklyBalance`, `.whyToday` identifiers; no green/red alone

3. **`Features/Coach/YourWeekView.swift`** — New screen:
   - Strength days vs 2-day guideline floor
   - Aerobic moderate-equivalent minutes vs 150-minute floor
   - Seven-day adaptive outline (hard/easy/rest labels)
   - VO2max latest/trend with protocol and date
   - Tap-to-swap planned session filtered to eligible alternatives
   - "Your week" is a push destination from the weekly context section of the Coach card

4. **`Features/Coach/WhyThisTodayView.swift`** — New screen:
   - Sections in order:
     1. "What you did" — exact relevant events/timestamps
     2. "What Coach ruled out" — deferred/blocked candidates and next eligible time
     3. "Why this won" — weekly deficit, recovery overlap, preference, confidence
     4. "Evidence" — citation cards for relevant studies
     5. "Policy" — plain-language line identifying conservative defaults
   - Pushed from "Why this today" link on Coach card
   - Accessibility labels for eligibility time, moderate-equivalent minutes, deferred reasons

5. **`Features/Home/ReadinessCheckInView.swift`** — Optional new view:
   - Four 1–5 sliders: muscle soreness, fatigue/energy, sleep quality, stress/mood
   - Yes/no "pain or illness concern" with safety copy
   - Never required; missing readiness lowers confidence, keeps conservative time gates
   - Accessible: no hidden pain diagnosis, clear neutral language

6. **`Features/Home/HomeView.swift`** — Update navigation destinations:
   - Add `HomeRoute.yourWeek` → `YourWeekView`
   - Add `HomeRoute.whyToday` → `WhyThisTodayView`
   - Add `HomeRoute.readinessCheckIn` → `ReadinessCheckInView`
   - `CoachInsightsView` updated to accept `CoachDecision` or kept for backward compat

7. **`Features/Coach/CoachAboutView.swift`** — Update copy:
   - Describe recovery-aware, balanced-fitness approach
   - Explain conservative policy vs evidence-backed claims

**Decision recomputation triggers:**
- Workout completion (strength or cardio)
- Workout deletion/restoration
- HealthKit sync importing new workouts
- Readiness check-in submission
- Assessment completion
- Program selection change

Each trigger recomputes `CoachFacts → CoachDecision` and the UI re-renders.

**Accessibility checklist:**
- No green/red alone; paired with symbol + text
- Coach card as accessibility group, CTA and science links separately actionable
- Exact a11y labels for eligibility time, moderate-equivalent minutes
- Dynamic Type must not truncate recommendation, recovery reasons, or CTA

**Acceptance criteria:**
- App builds for iOS simulator
- Coach card renders correct state after full-body session (Recovery/Easy Aerobic, not Train)
- `coach.card.nextEligible` shows tomorrow's time
- "Why this today" lists deadlift under ruled out
- Primary CTA launches exact `CoachSession.launchPayload`
- Deleting/restoring a workout recomputes the decision
- Dynamic Type does not truncate CTA or reason text

---

### Phase 6 — Science Cleanup

**Branch:** `phase-6-science-cleanup`  
**Depends on:** `phase-5-ui-migration`

**Scope:**

1. **`Citation.swift`** — Add 11 new citations:
   - `acsmResistance2026`, `whoPhysicalActivity2020`, `usPhysicalActivity2018`
   - `pellandDoseResponse2026`, `ramosCampoSplit2024`
   - `parejaBlancoRecovery2020`, `sawMonitoring2016`, `meeusenOvertraining2013`
   - `schumannConcurrent2022`, `crowleyVO2Intensity2022`, `poonHIIT2024`
   - Add to `all` array

2. **`docs/CITATIONS.md`** — Full audit pass:
   - Add entries for all 11 new citations, each with:
     - Exact claim supported
     - Population and important limitation
     - Which rule/policy uses it
     - Whether threshold is evidence-backed or app policy
   - Correct `frequencyMeta` entry: volume-equated frequency has no meaningful independent hypertrophy effect; distribute volume based on schedule, quality, and recovery
   - Correct `volumeDoseResponse` entry: remove implication that MEV/MAV/MRV cutoffs are validated; note they're heuristic starting ranges
   - Correct `amirthalingamGVT` entry: note the study found no advantage to 10 sets over 5

3. **`VolumeLandmarks.swift`** — Deprecation pass:
   - Add `VolumeGuidance` struct: `observedFractionalSets`, `startingTargetRange`, `personalBaselineRange`, `trend: DoseTrend`, `confidence: FactConfidence`
   - Add `@available(*, deprecated, message:)` to `VolumeBands.mev`, `.mav`, `.mrv` properties
   - Add `@available(*, deprecated, message:)` to `VolumeZone` cases
   - Add `DoseTrend` enum
   - Keep old types compiling, route through new types

4. **Preset audit (`WorkoutPlan.swift`):**
   - Every preset description: replace "validated by" with "informed by"
   - GVT 10×10: remove from automatic Coach selection OR add evidence caveat label; keep only as user-chosen advanced template
   - 5×5, 5/3/1, DUP, etc.: audit descriptions to say "informed by" not "validated by"

5. **Deload rule change (`RecommendationRule.swift`):**
   - Replace single-week e1RM decline → 10% deload with repeated/corroborated evidence + readiness check
   - Single-week decline → lower confidence, flag for monitoring, don't trigger deload
   - Two consecutive weeks decline + corroborating readiness → deload recommendation

6. **Cardio prescription change (`RecommendationRule.swift`):**
   - Remove "Beginner → Norwegian 4×4" default
   - Inactive/beginner: build consistency with 20–30 min moderate work, 2–3 times/week
   - Remove `cardioSIT` as automatic prescription (keep assessment but stop auto-prescribing)
   - Add `cardioModerate` rule for general aerobic prescription

**Tests to add:**

- **`CitationIntegrityTests.swift`** — Every in-code citation ID exists in `CitationRegistry.all`; every user-visible claim has a citation
- **`ScienceCopyTests.swift`** — No output contains "overtrained" or "overtraining syndrome"; no output calls 150min universally optimal; no output calls fixed set bands MRV/MEV without individual evidence; every product heuristic labeled policy

**Acceptance criteria:**
- `swift test` passes including citation integrity tests
- No user-visible text claims to diagnose overtraining
- All preset descriptions use "informed by" language
- GVT not auto-recommended by Coach
- Frequency copy is corrected
- `docs/CITATIONS.md` and `CitationRegistry` agree

---

### Phase 7 — Rollout and Cleanup

**Branch:** `phase-7-rollout`  
**Depends on:** `phase-5-ui-migration` + `phase-6-science-cleanup`

1. **Feature flag** — Add `recoveryAwareCoachV2` boolean flag in `AppSettings` / `UserDefaults` (default: `true` in debug, `false` in release until validated)
   - When disabled: use old `RecommendationEngine` path
   - When enabled: use new `CoachDecisionEngine` path

2. **Debug logging** — In debug builds only:
   - Log: candidate list → eligibility decision → score → final decision
   - Strip all personal data (exercise names OK, weights NOT)
   - Enable via `UserDefaults` key

3. **Decision export** — Add "Export coach reasoning" button in Settings (debug only):
   - Exports last `CoachDecision` as JSON
   - For bug reports only, includes anonymized facts and decisions
   - Personal data stripped (no weights, no body parts with weight context)

4. **Legacy engine removal** — After parity tests pass and release is validated:
   - Remove old `RecommendationEngine.pickRoutine` from coach path
   - Keep `RecommendationEngine.run` for backward-compat feature flag (one release)
   - Remove legacy cold-start "squat bench deadlift" default
   - Remove `TrainingFacts.daysSinceLastSession` as sole recovery signal
   - Archive or remove `VolumeZone` old cases if fully replaced

5. **Migration tests** — Ensure:
   - Existing SwiftData store opens and migrates with new `importedWorkoutKindRaw` field
   - Old `.other` cardio rows still function (unknown import)
   - All existing tests pass on migrated store

**Acceptance criteria:**
- Feature flag toggles between old and new engine
- Legacy engine removal after confirmed parity
- `swift test` passes full test suite
- App build + affected UI tests pass (note: UI tests may need environment reset)

---

## 4. Required Test Matrix

### Recovery invariants (Phase 3)
| # | Scenario | Expected |
|---|----------|----------|
| R1 | Full-body 42min ago (squat, bench, deadlift) | All three progressions deferred; easy aerobic or rest primary |
| R2 | Deadlift 23h59m ago | Exact deadlift hard work deferred |
| R3 | Deadlift 24h01m ago, posterior chain hard <48h | Hard hinge still deferred by pattern gate |
| R4 | Low-volume technique work, low RPE, good readiness | Non-hard technique candidate eligible, hard progression not |
| R5 | Failure + high RPE + poor readiness | 72h conservative window |
| R6 | Upper-body strength yesterday | Easy run eligible; hard full-body with bench blocked |
| R7 | Lower-body strength today | Sprint/HIIT deferred; easy walk/cycle eligible |
| R8 | Unknown imported HK strength today | Hard full-body deferred, easy aerobic eligible |
| R9 | Pain/illness concern | Hard candidates blocked; no diagnosis text |

### Balance and cardio (Phase 3)
| # | Scenario | Expected |
|---|----------|----------|
| B1 | 2 strength days, 0 aerobic minutes | Moderate aerobic outranks strength progression |
| B2 | 0 strength, 150 aerobic min, all muscles eligible | Strength wins |
| B3 | 75 vigorous minutes | Counts as 150 moderate-equivalent |
| B4 | Missing HR intensity | Minutes retain low-confidence classification |
| B5 | Same-protocol VO2max | Values trend; cross-protocol do not |
| B6 | Beginner, no cardio history | Moderate session primary; not SIT or 4×4 |

### Rolling-window boundaries (Phase 2)
| # | Scenario | Expected |
|---|----------|----------|
| W1 | Sunday workout, reference time Monday | Remains in facts if <7d old |
| W2 | Exactly 7d ago event | Drops out deterministically |
| W3 | `now` injectable in every test | No wall-clock time in engine tests |
| W4 | In-progress sets | Block conflicts, don't count as completed dose |

### UI and launch integrity (Phase 5)
| # | Scenario | Expected |
|---|----------|----------|
| U1 | Full-body just completed | Card state = Recovery or Easy Aerobic |
| U2 | `coach.card.nextEligible` | Shows tomorrow's time |
| U3 | "Why this today" | Lists deadlift under ruled out |
| U4 | CTA launch | Exact `CoachSession.launchPayload` |
| U5 | Delete/restore workout | Decision recomputes |
| U6 | Dynamic Type | CTA and reason don't truncate |

### Science integrity (Phase 6)
| # | Requirement |
|---|-------------|
| S1 | Every evidence claim has a citation |
| S2 | Every product heuristic labeled as policy |
| S3 | No "overtrained" / "overtraining syndrome" as diagnosis |
| S4 | No "150 minutes universally optimal" |
| S5 | No fixed-set-band MRV/MEV without individual evidence |

---

## 5. File-by-File Implementation Order

```
Phase 1 — Reproduce bug
  NEW  CadenceCore/Tests/CadenceCoreTests/CoachRecoveryRegressionTests.swift

Phase 2 — Events + facts
  NEW  CadenceCore/Sources/CadenceCore/MovementPattern.swift
  NEW  CadenceCore/Sources/CadenceCore/TrainingEvent.swift
  NEW  CadenceCore/Sources/CadenceCore/CoachFacts.swift
  NEW  CadenceCore/Tests/CadenceCoreTests/TrainingEventTests.swift
  NEW  CadenceCore/Tests/CadenceCoreTests/CoachFactsTests.swift

Phase 3 — Eligibility + decision engine
  NEW  CadenceCore/Sources/CadenceCore/SessionEligibilityPolicy.swift
  NEW  CadenceCore/Sources/CadenceCore/CoachSession.swift
  NEW  CadenceCore/Sources/CadenceCore/CoachDecision.swift
  NEW  CadenceCore/Sources/CadenceCore/WeeklyPlan.swift
  NEW  CadenceCore/Tests/CadenceCoreTests/SessionEligibilityPolicyTests.swift
  NEW  CadenceCore/Tests/CadenceCoreTests/CoachDecisionEngineTests.swift
  NEW  CadenceCore/Tests/CadenceCoreTests/WeeklyPlanTests.swift

Phase 4 — HealthKit integrity
  EDIT CadenceCore/Sources/CadenceCore/Models.swift           (+importedWorkoutKindRaw)
  EDIT CadenceCore/Sources/CadenceCore/Services.swift          (+ImportedWorkoutKind enum)
  EDIT CadenceCore/Sources/CadenceCore/WorkoutRepository.swift (ingest changes)
  EDIT Cadence/Cadence/Services/HealthKitProvider.swift        (mapping)
  NEW  CadenceCore/Tests/CadenceCoreTests/ImportedWorkoutKindTests.swift

Phase 5 — UI migration
  EDIT Cadence/Cadence/Features/Home/HomeView.swift
  REWRITE Cadence/Cadence/Features/Coach/CoachCardView.swift   (state-driven)
  NEW  Cadence/Cadence/Features/Coach/YourWeekView.swift
  NEW  Cadence/Cadence/Features/Coach/WhyThisTodayView.swift
  NEW  Cadence/Cadence/Features/Home/ReadinessCheckInView.swift
  EDIT Cadence/Cadence/Features/Coach/CoachAboutView.swift
  EDIT Cadence/Cadence/Features/Coach/CoachInsightsView.swift

Phase 6 — Science cleanup
  EDIT CadenceCore/Sources/CadenceCore/Citation.swift          (+11 citations)
  EDIT CadenceCore/Sources/CadenceCore/VolumeLandmarks.swift   (deprecate MEV/MAV/MRV)
  EDIT CadenceCore/Sources/CadenceCore/RecommendationRule.swift (deload/cardio changes)
  EDIT CadenceCore/Sources/CadenceCore/WorkoutPlan.swift       (preset descriptions)
  EDIT docs/CITATIONS.md
  NEW  CadenceCore/Tests/CadenceCoreTests/CitationIntegrityTests.swift
  NEW  CadenceCore/Tests/CadenceCoreTests/ScienceCopyTests.swift

Phase 7 — Rollout
  EDIT Cadence/Cadence/App/AppSettings.swift                   (+feature flag)
  EDIT CadenceCore/Sources/CadenceCore/RecommendationEngine.swift (legacy adapter)
```

---

## 6. Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking existing users' SwiftData stores | All schema changes are additive (optional/defaulted fields); migration tested |
| Coach card regression for existing users | Feature flag `recoveryAwareCoachV2` allows rollback |
| Overly conservative recovery gates boring users | All gates are configurable constants, not hardcoded; defaults match evidence-backed guidance |
| Cardio/aerobic emphasis alienating strength-focused users | Training goal still drives relative priority; aerobic floor is guideline, not prescription |
| New screens increasing app complexity | "Your week" and "Why this today" are detail/push screens, not new tabs; main flow unchanged |
| Science text audit breaking UI layout | All copy changes use existing UI components; Dynamic Type testing throughout |

---

## 7. Open Questions

1. **Readiness check-in frequency:** Should the prompt appear once daily at a consistent time, or on next app open after 24h since last entry? (Design says optional, never required.)

2. **Beginner A/B exercise selection:** The design specifies pattern-based selection (squat pattern, hinge pattern, etc.) without specific exercise names. Should the engine map each pattern to the user's most-trained exercise from the library, or use canonical defaults (Back Squat for squat, Romanian Deadlift for hinge, etc.)?

3. **"Tap to swap" on Your Week:** This implies a picker UI for eligible alternatives. Should this reuse existing `PlanningView`/`RoutineDetailView` components or be a lightweight inline picker?

4. **GVT fate:** The design says "keep it only as a user-chosen advanced template with an evidence caveat, or remove it." Should we keep or remove?
