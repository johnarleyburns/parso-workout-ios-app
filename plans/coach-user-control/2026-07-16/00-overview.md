# Plan: "Coach suggests, it does not proscribe" — same-day load, honest scheduling, and user control

## Context

Investigating `Cladiron-Export-2026-07-14.json.gz` (userAge **50**, `strengthDaysPerWeek: 5`,
`cardioDaysPerWeek: 6`, `allowsTwoADays: true`, `sameDayCardioTiming: separateLater`,
fixed rest = Sunday) surfaced a cluster of bugs and a philosophy gap. On 7/15 the user did
HIIT (Tabata) then boxing and the coach **still** prescribed "Easy cycle," never scheduled the
requested 5 strength days (only 3), and the "Your Plan" UI hid the second same-day workout and
had dead taps. Underlying all of it: the coach behaves as if it **prescribes** the week, when
the user wants it to **suggest** and always leave them in control.

This plan fixes the mechanics **and** codifies the principle:

> **Coach SUGGESTS, it does not PROSCRIBE.** Every coach output is advice, never a lock.
> The user's stated targets (days/week, two-a-days) win over the coach's automatic recovery
> logic; the coach may *recommend* going lighter, but never silently drops a day the user asked
> for, and every screen leaves a one-tap path to do something else.

Verified root causes (file:line grounded):

1. **Cardio intensity is HR-average-only and age-blind.** `TrainingEvent.from(cardio:)`
   (`CadenceCore/Sources/CadenceCore/TrainingEvent.swift:263-275`) computes intensity from
   `avgHR / (220 - 30)` — hardcoded age 30 (true maxHR for a 50yo is 170, not 190) — and
   defaults to `.moderate` when HR is absent. HIIT/boxing average out below 0.80 of maxHR and
   are never forced vigorous. Result: **none** of the user's intense sessions counted as "hard."
2. **Same-day cardio is invisible to load/recovery.** `CoachFacts.computeRecovery`
   (`CoachFacts.swift:324-428`) processes **strength events only** (`guard case .strength`);
   readiness (`ReadinessFusion`/`PassiveReadiness`) has no cardio input; `CoachAddOnEngine`'s
   `hardDoneToday` (`CoachAddOnEngine.swift:13`) keys off `isHard`. So after HIIT+boxing the
   coach still nags "Add easy cardio" (`CoachAddOnEngine.swift:47-74`) and ranks "Easy cycle"
   top (`CoachDecision.swift:715-718`; cycle wins the id-sort tiebreak at `:655-658`).
3. **Weekly planner forces recovery days that eat the user's strength target.**
   `WeeklyPlan.futureSessions` (`WeeklyPlan.swift:397-496`) counts every planned easy/moderate
   cardio day as a "hard day" (`:349-352`), trips a hard-streak recovery gate (`:436-442`) that
   returns a forced **Recovery** day, and only adds cardio alongside strength awkwardly
   (`:476-489`). With 6 planned cardio days this repeatedly converts strength slots to Recovery
   → 3 strength days instead of 5.
4. **"Your Plan" UI collapses & dead-ends multi-workout days.** History pass keeps a
   single-value-per-day cardio dict and overwrites the 2nd cardio
   (`WeeklyPlan.swift:183, 201-204`); completed-day tap resolves to one strength-preferred
   `HistorySummaryRoute` (`YourWeekView.swift:240-249`); `PlannedSession` carries no cardio
   prescription and `PlannedDayPreviewView` renders detail for strength only
   (`PlannedDayPreviewView.swift:22-33`); a **today** planned row is not tappable at all
   (`YourWeekView.swift:233-235`).
5. **Home offers no "different cardio" / "strength anyway" control.** The "Not feeling it? Pick
   another" link shows only for cardio primaries (`CoachDecisionCardView.swift:434-440`) and
   Alternatives lists only scored cardio swaps (`CoachAlternativesView.swift:52-54`). No entry
   to the full cardio picker (`WorkoutTypePicker`, already built) or to a best-fit strength plan
   preview (`WorkoutPlanEditor`, already built) when strength isn't scheduled.

Decisions from the user (this session):
- **Readiness:** *Notice it, stop nagging.* Count same-day HIIT/boxing as real intense load,
  drop redundant easy-cardio suggestions, surface "you already trained hard today" — but
  **never block or downgrade strength.** Assume HIIT/boxing are **always** intense regardless
  of HR; also fix the age/averaging bug so tracked-HR sessions classify correctly.
- **Scheduling:** *User's scheduled days/week trumps coach recovery.* Never force a recovery day
  that drops a strength or cardio day the user asked for. The coach may **recommend** a lighter
  day when it sees several consecutive hard days, but athletes routinely train 6 hard days/week,
  so don't be trigger-happy. With **two-a-days on, plan strength AND cardio every non-rest day**
  and modulate intensity/mix rather than dropping days.
- **Control UI:** *Contextual + two-a-day aware.* On a two-a-day the card lets the user pick a
  different strength **and** a different cardio; "Do a different cardio" and "Do strength anyway"
  appear where relevant.

Work follows the repo methodology (`CLAUDE.md` §Dev methodology): design docs land under
`plans/coach-user-control/2026-07-16/`, then one branch+PR per phase. Logic lives in
`CadenceCore`/`CadenceFeatures` (headless `swift test`); UI is thin. Schema changes are additive
only. **Every new coach output must cite science** (`CitationRegistry` + `CitationLink`; keep
`docs/CITATIONS.md` in sync).

---

## Phase 1 — Cardio intensity truth (CadenceCore)

**Goal:** intense cardio reads as intense, so downstream load/recovery/nagging logic can see it.

Edit `TrainingEvent.from(cardio:)` (`TrainingEvent.swift:263-289`):
- **Modality floor:** HIIT, boxing, and any `isInterval` session are classified **at least
  `.vigorous`**, independent of HR (user directive: "assume HIIT is ALWAYS intense"). HR may
  only raise, never lower, these.
- **Real age for maxHR:** thread the user's age into the classifier and use `220 - age`
  (fall back to 30 only when age is unknown). Plumb `userAge`/DOB from preferences into the
  `TrainingEvent.from(cardio:)` call sites (via `CoachFacts.make` inputs) — additive parameter
  with a safe default so existing callers/tests compile.
- **Peak-aware for intervals:** for interval/combat modalities, prefer time-in-zone or
  `maxHeartRate`-anchored classification over raw average (a HIIT session whose peaks hit maxHR
  is vigorous even if the average sits at 0.7). Keep it simple: `vigorous` if modality-floor OR
  `avgHR ≥ 0.80·maxHR` OR `peakHR ≥ 0.90·maxHR`.
- **No-HR default:** HIIT/boxing with no HR → `.vigorous` (not `.moderate`); other modalities
  keep the current moderate default.

**Tests (`CadenceFeaturesTests`/`CadenceCoreTests`):** table-driven cases proving each of the
user's 7/06–7/13 sessions now classifies vigorous/hard; age-50 vs age-30 maxHR; no-HR HIIT →
vigorous; a genuine easy walk stays easy.

---

## Phase 2 — Same-day load awareness: coach stops nagging (CadenceCore)

**Goal:** once intense cardio is done today, drop redundant easy-cardio pushes and say so —
without touching strength.

- **`hardDoneToday` counts cardio:** with Phase 1, same-day HIIT/boxing now flip `isHard`, so
  `CoachAddOnEngine` (`CoachAddOnEngine.swift:13,47-74`) already suppresses "Add easy cardio."
  Verify and add a guard: if intense cardio (or ≥N cardio sessions) already logged today, do
  **not** emit the easy-cardio add-on or rank easy-aerobic as the daily primary.
- **De-prioritize redundant easy cardio in the daily decision:** in `CoachDecision`
  scoring (`scoreSessionBase`, `CoachDecision.swift:715-718` and `sameDayDamping` `:606-631`),
  when today already has intense cardio, apply a **negative** adjustment to easy-aerobic
  candidates so a still-needed strength session (or "you're done") outranks "Easy cycle."
  Strength scoring is untouched — never suppressed.
- **New cited insight:** surface a free (non-gated) coach *insight* "You've already logged
  HIIT + Boxing today (~2 intense sessions)" derived from `facts.todayCompletedEvents`. Wire
  through `CoachSnapshotBuilder`/`HomeCoachModel` as an insight (not a prescription). Attach
  citations (reuse an existing recovery/concurrent-training ID such as
  `meeusenOvertraining2013`; add a concurrent-training citation to `CitationRegistry` +
  `docs/CITATIONS.md` if none fits). Render with `CitationLink`.

**Tests:** given today = {HIIT, boxing}, assert (a) no easy-cardio add-on, (b) easy-aerobic not
the primary, (c) strength still eligible/selectable, (d) insight text + resolved citation.

---

## Phase 3 — Weekly planner: honor targets, recommend (not force) recovery, two-a-days everywhere

**Goal:** the plan reflects what the user asked for; recovery is advice, not a silent day-drop.

Rework `WeeklyPlan.futureSessions` (`WeeklyPlan.swift:397-496`) and the projection loop
(`:340-360`):
- **Targets trump auto-recovery.** Remove the forced `recoveryNeeded → return Recovery`
  short-circuit (`:437-442`) as a *day-replacer*. Fixed rest days (`restPreference`) remain the
  only true non-training days.
- **Two-a-days fill every non-rest day.** When `allowsTwoADays`, every non-rest day gets **both**
  a strength and a cardio `PlannedSession` until weekly targets are met; when targets are met,
  keep going but **modulate intensity/mix** (lighter strength, easy vs moderate vs VO₂ cardio)
  rather than dropping a modality. Respect `sameDayCardioTiming` for the `timingNote`
  ("separate, later").
- **Stop counting easy/moderate planned cardio as "hard days."** In the projection
  (`:349-352`), only genuinely hard sessions (hard strength, vigorous/interval cardio) mark a
  hard day; easy/moderate cardio does not. This alone stops the recovery-gate cascade that ate
  strength days.
- **Recommend, don't force, recovery.** When the *observed real* hard-streak is long (e.g. ≥6
  consecutive genuinely-hard days), attach a **non-blocking** recommendation to that day
  ("Consider a lighter session — N hard days in a row") via a `PlannedSession` flag /
  `timingNote` + insight, but still schedule the user's strength+cardio. Calibrate the threshold
  so a normal 6-hard-day athlete week is fine; surface the nudge only past that. Cite
  (`meeusenOvertraining2013`).
- **Split rotation unchanged in spirit:** keep upper/lower focus rotation
  (`useSplit`, `focusRecoveryEligible`) for *which* muscles, but never let it zero out a day the
  user scheduled.

**Tests:** with the export's prefs (5 strength, 6 cardio, two-a-days, Sun rest), assert the
generated week has **5 strength days and 6 cardio days**, Sunday rest, no forced Recovery day,
both modalities on non-rest days, and a "consider lighter" recommendation only after the long
real streak.

---

## Phase 4 — "Your Plan" UI: honest multi-workout days (CadenceFeatures + Views)

**Goal:** every workout a day contains is visible and tappable — completed or planned, strength
or cardio, one or two.

- **Stop collapsing same-day cardios.** Replace the single-value `cardioEventsByDay` dict
  (`WeeklyPlan.swift:183, 201-204, 222-227`) with a **list** of cardio events per day; append
  one `PlannedSession` per logged cardio (HIIT **and** boxing both show). `DayOutline.sessions`
  is already a list (`:81-108`); the row already `ForEach`es it (`YourWeekView.swift:353`).
- **Completed strength+cardio day → view either.** Replace the single strength-preferred
  `HistorySummaryRoute` (`YourWeekView.swift:215-225, 240-249`) with **per-chip navigation**
  (each `PlannedSession` chip taps to its own `HistorySummaryRoute`) or a small chooser when a
  day has >1 completed workout. Reuse existing `.strength`/`.cardio` routes
  (`HistoryView.swift:9-12`).
- **Planned cardio carries a real prescription.** Add additive fields to `PlannedSession`
  (`WeeklyPlan.swift:45-75`): `cardioDurationMinutes`, `cardioIntensityZone`/target-HR,
  `cardioModality`. Populate future cardio at `WeeklyPlan.swift:485-488` (reuse
  `plannedModerateEquivalentMinutes` `:551-558` and `Recommendation.cardioPrescription` shape).
- **Planned detail renders cardio.** Add a cardio branch to `PlannedDayPreviewView`
  (`PlannedDayPreviewView.swift:22-33, 45`) showing modality, duration, target zone/HR, and a
  cited "why this" — mirroring the strength branch. Reuse `CoachSessionKind` labels.
- **Today's planned row is tappable.** Fix the fall-through (`YourWeekView.swift:233-235`) so a
  today/planned row opens `PlannedDayPreviewView` like future rows do.
- Applies to both "This Week" (`currentWeekDays`) and "Planned (next week)" (`nextWeek`) rows.

**Tests:** `swift test` on `WeeklyPlan.generate` (two cardios both present; planned cardio has
prescription fields). UI verified by the run/verify skill (no new XCUITests — smoke suite is
fixed per `CLAUDE.md`).

---

## Phase 5 — Home control affordances: contextual + two-a-day aware (Views + CoachRouter)

**Goal:** the user can always redirect the coach with one tap.

- **"Do a different cardio" → full cardio picker.** Add a row to `CoachAlternativesView`
  (`CoachAlternativesView.swift`) that launches the existing `WorkoutTypePicker`
  (`WorkoutTypePicker.swift`, already wired on Home at `HomeView.swift:421-427` via
  `cardioPickerPresented`/`start(_:)`). Reuse the one-runloop deferral pattern
  (`HomeView.swift:1032-1035`) to avoid present-races-dismiss.
- **"Do a strength workout anyway."** When today's plan has no strength, add a card affordance
  that generates a best-fit strength `CoachSession` (`CoachSession.fullBodyStrengthExercises` /
  `buildStrengthExercises`, `CoachSession.swift:489-569`; ranking via `trainedExerciseCandidates`
  `:626-669`), converts with `EditablePlan.from(coach:)` (`EditablePlan.swift:86-108`), and
  routes to `HomeRoute.workoutEditor` → `WorkoutPlanEditor` (the pre-strength preview screen,
  `WorkoutPlanEditor.swift`) for the user's perusal before starting. This reuses the existing
  `WeightsStartView` "Coach's Workout" path (`WeightsStartView.swift:19-49`) but surfaces it
  contextually.
- **Two-a-day card shows both components, each swappable.** When the day is a two-a-day
  (strength + cardio), `CoachDecisionCardView` presents both, each with its own "pick another /
  different" (strength → Alternatives-of-strength or plan editor; cardio → cardio Alternatives /
  full picker). Relax the cardio-only gate on the alternatives link
  (`CoachDecisionCardView.swift:434-440`) so control is available per component.

**Tests:** `CoachRouter`/model-level `swift test` for the strength-anyway generation path
(produces a valid `EditablePlan`); UI via run/verify.

---

## Phase 6 — Codify the principle (docs, no behavior change)

- **README:** add a "Coach suggests, it does not proscribe" design-principle section (user is
  always in control; targets win over auto-recovery; every coach screen leaves an escape hatch).
- **`docs/REQUIREMENTS.md`:** add the principle as a cross-cutting NFR/design constraint the
  coach engine and UI must honor; reference it from the field-testing / coach sections.
- **`CLAUDE.md`:** one durable line under the coach/architecture notes so future work upholds it.
- **`docs/CITATIONS.md` + `CitationRegistry`:** ensure every new insight/recommendation ID added
  in Phases 2–4 has a matching entry (HARD RULE); add a concurrent-training/interval-recovery
  citation if the existing registry lacks a suitable one.

---

## Critical files

| Area | File |
|---|---|
| Cardio classification | `CadenceCore/Sources/CadenceCore/TrainingEvent.swift` |
| Load/recovery/readiness | `CadenceCore/Sources/CadenceCore/CoachFacts.swift`, `ReadinessFusion.swift`, `PassiveReadiness.swift` |
| Nagging / add-ons | `CadenceCore/Sources/CadenceCore/CoachAddOnEngine.swift` |
| Daily decision/scoring | `CadenceCore/Sources/CadenceCore/CoachDecision.swift`, `CoachSession.swift` |
| Weekly planner | `CadenceCore/Sources/CadenceCore/WeeklyPlan.swift` |
| Your Plan UI | `Cadence/Cadence/Features/Coach/YourWeekView.swift`, `PlannedDayPreviewView.swift` |
| History routes | `Cadence/Cadence/Features/History/HistoryView.swift` |
| Home card / alternatives | `Cadence/Cadence/Features/Coach/CoachDecisionCardView.swift`, `CoachAlternativesView.swift` |
| Cardio picker / strength start / plan preview | `Cadence/Cadence/Features/Home/WorkoutTypePicker.swift`, `WeightsStartView.swift`, `WorkoutPlanEditor.swift` |
| Routing / plan conversion | `CadenceCore/Sources/CadenceFeatures/CoachRouter.swift`, `EditablePlan.swift` |
| Snapshot assembly | `CadenceCore/Sources/CadenceFeatures/HomeCoachModel.swift`, `CadenceCore/Sources/CadenceCore/CoachSnapshotBuilder.swift` |
| Citations | `CitationRegistry`, `docs/CITATIONS.md` |
| Docs/principle | `README.md`, `docs/REQUIREMENTS.md`, `CLAUDE.md` |

## Verification

- **Per phase:** `cd CadenceCore && swift test` is the reliable gate (Mac toolchain). Add
  focused tests for each behavior change (classification tables, no-nag-after-cardio,
  5-strength/6-cardio week, two-cardio-day, planned-cardio prescription).
- **Regression fixture:** load `Cladiron-Export-2026-07-14.json.gz` (age 50, the real prefs)
  into a `swift test` fixture and assert the corrected end-to-end behavior: 7/06–7/13 intense
  cardio classifies hard; a simulated "HIIT+boxing done today" yields no "Easy cycle" primary
  and no easy-cardio add-on; the generated week has 5 strength + 6 cardio days with only
  Sunday rest.
- **UI:** use the `run`/`verify` skills to drive the app — confirm Your Plan shows both same-day
  workouts and both are tappable, planned cardio opens a real detail, "Do a different cardio"
  opens the full picker, and "Do strength anyway" opens the plan editor. The XCUITest smoke
  suite stays fixed (`CLAUDE.md`); new coverage is `swift test`.
- **CI:** `scripts/check-test-pyramid.sh` must stay green (import ban, ≤12 UI tests, 400-LOC
  Features-file budget). Follow the mandatory post-task checklist (commit → merge → push →
  monitor CI) per phase.
