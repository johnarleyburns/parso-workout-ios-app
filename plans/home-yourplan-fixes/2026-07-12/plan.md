# Plan: Home / Your Plan bug-fix batch + cardio HR-zone bar

## Context

The user reported 7 defects plus 1 feature request while using Cladiron (internal
codename Cadence), the iPhone strength coach. They span the Home ("Workout") tab, the
workout edit flow, the tab bar, and the "Your Plan" / "Your Week" coaching surface. The
throughline: the Home coach snapshot and the weekly planner are showing stale,
mislabeled, or under-detailed information, and the planner's recovery model is too coarse
to honor a user who trains strength 5×/week. The outcome we want: timestamps and "This
Week" reflect the *workout's* date; editing a past workout is inert (no live-session
behavior); planned days are fully inspectable; the coach actually schedules the user's
real training frequency using split-routine science; and cardio intensity is shown as a
readable zone bar with a correct citation.

Decisions already made with the user (do not re-litigate):
- **#3** — tapping the Home "What you did" card opens **the whole workout** (session
  detail), not per-exercise navigation.
- **#6** — a tapped PLANNED (NEXT WEEK) day shows the **full concrete exercise list**
  (sets/reps/RIR per movement), not a generic one-liner.
- **#7** — the coach should **allow back-to-back strength days (splits)** AND **infer the
  target frequency from actual history**, so a 5×/week lifter sees ~5 planned strength days.

## Ground rules

- Logic in `CadenceCore` (pure, `swift test`-verifiable); UI thin on top. Schema/model
  changes are **additive only** (optional/defaulted) per CLAUDE.md.
- **HARD RULE:** every new/changed coaching output must render tappable citations via
  `CitationLink` + `CitationRegistry.citation(forId:)`. Never show raw IDs.
- Verify with `swift test` (CadenceCore) and `xcodebuild` UI suite before committing.

---

## Fix 1 — "What you did" shows entry time, not the workout's date

**Root cause.** The relative-time string is built from `TrainingEvent.end`, which maps to
`session.endedAt` (finalize/entry time), not `session.date` (the user's chosen workout
time). See `CoachDecision.swift:269,285` (`formatRelative(lastStrength.end, now)` /
`...lastCardio.end...`) and `TrainingEvent.swift:156,227` where `end = session.endedAt`.
`formatRelative` is `CoachDecision.swift:802-808`.

**Fix.** In `CoachDecision.swift`, format the "What you did" time from the event's
**start** (`= session.date`) instead of `.end`, for both the strength and cardio facts.
Also set the fact's `occurredAt` sort key from `.start` for consistency
(`CoachDecision.swift:271,287`) so ordering matches the displayed time. `HomeView.swift:801`
already renders `fact.value` — no UI change needed.

**Files:** `CadenceCore/Sources/CadenceCore/CoachDecision.swift`.

**Tests (CadenceCore):** add a case in the CoachDecision tests: a session with
`date` = 12h ago and `endedAt` = 2h ago must produce a "What you did" value of "12h ago".

---

## Fix 2 — Editing a past workout starts the rest timer

**Root cause.** `SessionView.addSet(...)` starts the rest timer whenever a *new* set is
added, guarded only by `!isManualLog` (`SessionView.swift:1719-1721`). History-edit entry
points (`HomeView.swift:343`, `ProgressView.swift:51`) construct `SessionView(session:)`
with the default `isManualLog = false`, so correcting a past workout fires the timer.

**Fix.** Suppress the rest timer unless the session being edited **is the live active
session**. Add `active.strengthSession?.id == session.id` to the guard at
`SessionView.swift:1719` (the view already uses this exact "is-live" discriminator at
`SessionView.swift:383`). This also naturally covers back-dated logged sessions
(`session.isLogged`) without a new flag. Keep the existing `!isManualLog` term.

**Files:** `Cadence/Cadence/Features/Train/SessionView.swift`.

**Tests:** primarily a UI test — open a past workout from History, add/adjust a set,
assert the `RestTimerBar` (identifier in `RestTimer.swift`) does **not** appear. If the
rest-start condition can be extracted to a small pure helper, add a `swift test` for it;
otherwise rely on the UI test (`CadenceUITests`).

---

## Fix 3 — Tapping the Home "What you did" card does nothing

**Root cause.** `whatYouDidFactRow` (`HomeView.swift:784-808`) is a plain `HStack` with no
`Button`/`NavigationLink`; exercise names are an inert joined string. History rows, by
contrast, navigate (`HistoryView.swift:91` → `WorkoutSummaryView`; `ProgressView.swift:51`
→ `SessionView`).

**Fix (whole-card → the workout, per decision).** Wrap the strength/cardio "What you did"
row in a navigation that opens that workout's detail. The coach fact must carry the source
`WorkoutSession` id (the facts are built in `CoachDecision.swift` from
`lastStrength`/`lastCardio`); add an optional `sessionId: UUID?` (or reuse an existing id
field if present) to the `ObservedFact` used here, populate it, and in `HomeView` resolve
it back to the `WorkoutSession` and push the existing `.navigationDestination(for:
WorkoutSession.self)` (already registered at `HomeView.swift:343`). Reuse
`ExerciseDetailView` remains reachable from inside `SessionView` (`SessionView.swift:823-824,880-881`).
Add `.contentShape(Rectangle())` so the full row is tappable (see memory
`xcuitest-plain-button-spacer-hit-point`).

**Files:** `CadenceCore/.../CoachDecision.swift` (thread session id onto the fact),
`Cadence/Cadence/Features/Home/HomeView.swift`.

**Tests:** UI test — tap the "What you did" strength card on Home, assert navigation to the
session detail (existing identifier on `SessionView`).

---

## Fix 4 — Tab bar icons too close to the top

**Root cause.** `RootTabView.init()` (`RootTabView.swift:9-24`) sets a
`UITabBarAppearance` that only zeroes `titlePositionAdjustment`; nothing adds a top inset
to the icon, so the icon+label block sits flush to the top edge.

**Fix.** In the `UITabBarAppearance` config, add a small positive top inset to the icon
(via `stackedLayoutAppearance/inlineLayoutAppearance/compactInlineLayoutAppearance`
`.normal/.selected` `titlePositionAdjustment` and/or item `imageInsets` top) to push the
block down a few points. Apply consistently to all three layout appearances already
configured (`RootTabView.swift:16-21`). Keep the change conservative (a few pt) and verify
visually on iPhone.

**Files:** `Cadence/Cadence/App/RootTabView.swift`.

**Tests:** visual/manual via `/run` screenshot (layout constants aren't unit-testable);
the existing tab UI tests must still pass (tab items still hittable).

---

## Fix 5 — "This Week" doesn't refresh after editing a past workout's date

**Root cause.** The Home "This Week" strip renders from a cached `@State coachSnapshot`
(`HomeView.swift:89`) rebuilt only by `.task(id: coachSignature)` (`HomeView.swift:585`).
`CoachSignature` (`HomeView.swift:128-156`) keys on `sessions.count`, tokens, and settings
— **not** on session dates. The date edit (`SessionView.swift:655-657`) mutates
`session.date` and saves but never bumps `historyRefreshToken` /
`markWorkoutHistoryChanged()` (`HomeView.swift:603-608`), so the signature is unchanged and
the snapshot is stale until app restart.

**Fix.** When a session's date is edited, signal a history change. Cleanest: in the date
setter (`SessionView.swift:655-657`) post the same notification the Home
`workoutSaved`/history-changed path already observes (`HomeView.swift:615`, which calls the
token bump). That refires `.task(id: coachSignature)` and recomputes `weeklyBalance`. (Do
not widen `CoachSignature` to hash all session dates — a notification on the mutating edit
is cheaper and matches the existing pattern.)

**Files:** `Cadence/Cadence/Features/Train/SessionView.swift` (post notification on date
change); confirm the observer in `HomeView.swift`.

**Tests:** UI test — edit a past workout's date across a week boundary, return to Home,
assert the "This Week" count/strip changed without relaunch.

---

## Fix 6 — PLANNED (NEXT WEEK) day only shows a generic summary

**Root cause.** A planned day is modeled as coarse `PlannedSession` (kind + label only) in
`WeeklyPlan.swift:4-22`; `PlannedDayPreviewView` derives a single generic
`"3 sets · reps · ~RIR"` line (`PlannedDayPreviewView.swift:22-25,52-56`) from the goal —
there are no concrete exercises to show.

**Fix (full exercise list, per decision).** Attach a concrete strength prescription to
planned strength sessions and render it.

1. **Model (additive):** add optional `exercises: [RecommendedExercise]?` (and optionally a
   `SessionStructure`/focus label) to `PlannedSession` in `WeeklyPlan.swift`. Default `nil`
   keeps existing callers/JSON working.
2. **Generation:** when `WeeklyPlan.generate`/`futureSessions` emits a strength
   `PlannedSession`, populate its `exercises` by reusing the existing prescription
   generator **`CoachSession.buildStrengthExercises(facts:)`** (`CoachSession.swift:493`),
   which already produces `RecommendedExercise` objects with sets/`repsLow/High`/`rir` and a
   per-set `repLadder`, preferring the user's actual lifts (`mostTrainedExercises`). For a
   split week (Fix 7), generate exercises for that day's **focus** (upper/lower/push/pull)
   via the existing `SessionStructure`/`classifyStructure` machinery
   (`CoachPlanOptimizer.swift:259-287`) so days differ. **Reconciliation note for the
   implementer:** there is a parallel `CoachPlanOptimizer.optimize(...)` that already emits
   `plannedStrengthSessions: [CoachSession]` (full exercises on dates). Evaluate reusing its
   output to populate the planned days instead of re-deriving — pick one source of truth and
   document the choice in `current_state.md`.
3. **UI:** in `PlannedDayPreviewView`, when a strength `PlannedSession` has `exercises`,
   render the full list (exercise name + sets×rep-ladder + RIR) instead of the generic
   `strengthPrescription` line. Keep the cited-science section (currently `schoenfeld2021`).

**Files:** `CadenceCore/.../WeeklyPlan.swift`, `CadenceCore/.../CoachSession.swift` (reuse
only), `Cadence/Cadence/Features/Coach/PlannedDayPreviewView.swift`.

**Tests (CadenceCore):** a generated next-week strength day exposes a non-empty
`exercises` list with sane sets/reps; a split week yields differing focuses across
consecutive strength days. UI test: tap a PLANNED (NEXT WEEK) strength day, assert multiple
exercise rows render (not just one summary line).

---

## Fix 7 — Only 2 strength days planned when the user trains 5×/week

**Root cause (two compounding).**
1. `CoachSchedulePreferences.strengthDaysPerWeek` **defaults to 2** in every path
   (`CoachSchedulePreferences.swift:76,83,101`; onboarding `@State = 2`,
   `OnboardingView.swift:18`), so `strengthFloor` is often 2.
2. Even at 5, `futureSessions` structurally caps strength: `canStrength` requires
   `priorHardStreak == 0` (`WeeklyPlan.swift:319`) but every strength day is `isHard: true`
   (line 328), so the next day is blocked; moderate cardio also counts as "hard"
   (line 262); rolling rest every 3 days and recovery-after-3-hard further erode it.
   Net: ~2–3 strength/week regardless of preference.

**Fix.**
- **Infer target from history + honor preference.** In `WeeklyPlan.generate`, compute an
  **effective strength floor** = `max(schedulePreferences.strengthDaysPerWeek, observed
  recent weekly strength days)` where the observed count comes from
  `facts.rolling7dCompletedEvents` strength days (the user's real cadence). Use this
  effective floor in `futureSessions` instead of the raw preference. (Keep the stored
  preference authoritative as a floor; inference only raises it.) Confirm the clamp in
  `CoachSchedulePreferences` (currently max 5) accommodates the target; raise the max only
  if we intend to allow 6.
- **Allow splits (per-muscle recovery instead of whole-body block).** Relax the coarse
  "no consecutive hard days" gate so strength can land on consecutive days **when the days
  train different muscle groups / focuses**. The machinery exists: per-`BodyPart` recovery
  windows (`CoachFacts.RecoveryState.byBodyPart`), per-part eligibility
  (`SessionEligibilityPolicy.evaluateStrength`, `CoachPlanOptimizer.isExerciseEligible`),
  and split classification (`SessionStructure`/`classifyStructure`). Change the strength
  gate (`WeeklyPlan.swift:318-321`, and mirror in `CoachPlanOptimizer.hardStrengthAllowed`
  `:797-800` / `CoachDecision.generateTomorrowPreview` `:570` if reused) to consult
  per-body-part windows for a *rotated focus* rather than blanket `priorHardStreak == 0`.
  Assign each planned strength day a focus (upper/lower or push/pull/legs) so consecutive
  days hit different muscles — this dovetails with Fix 6's per-focus exercise generation.
- **Citations (HARD RULE).** The relaxed schedule is backed by existing IDs — cite them on
  the planned-week/frequency copy: `frequencyMeta` (Schoenfeld/Grgic/Krieger 2019,
  frequency), `ramosCampoSplit2024` (split routines), `parejaBlancoRecovery2020`
  (lift-specific 48h recovery justifying next-day different-muscle work). All already in
  `CitationRegistry` — no new citation needed here.

**Files:** `CadenceCore/.../WeeklyPlan.swift` (effective floor + split gating + focus
assignment), possibly `CadenceCore/.../CoachSchedulePreferences.swift` (clamp),
`CadenceCore/.../CoachPlanOptimizer.swift` / `CoachDecision.swift` (mirror gate if that path
is used), and the onboarding default if we want new users to start higher.

**Tests (CadenceCore):** given facts with 5 strength days in the trailing week and
`strengthDaysPerWeek = 2`, the generated next week schedules ~5 strength days on
distinct-focus consecutive days; given a whole-body/same-focus history, consecutive
same-muscle days are still blocked (recovery respected). Add a regression asserting the
frequency-related planned copy resolves its citation IDs.

---

## Fix 8 (new feature) — Cardio HR-zone bar on Your Plan (THIS WEEK) + zone-training citation

**Current state.** `YourWeekView.swift:145-167` renders "Cardio HR zones (this week)" as a
plain list of text rows (Z1..Z5 name + minutes), only for zones with minutes > 0.5. Time in
zone is **already computed**: `CardioZoneAggregator.weeklyZoneMinutes(sessions:age:)`
(`CardioZoneAggregator.swift:36`) → `[Int: Double]` per zone (1–5), consumed at
`YourWeekView.swift:39,258-268`. Zone bands/names live in `CardioMath.swift` (5 zones). No
per-zone color exists anywhere. The "The science" link is `tanakaMaxHR2001`
(`YourWeekView.swift:163`) — the max-HR paper the user wants replaced.

**Fix.**
1. **Stacked colored bar.** Add a horizontal stacked bar above/replacing the text rows,
   segmenting the total weekly minutes by zone proportion (read the existing
   `[Int: Double]` `zoneMinutes`; iterate the full Z1–Z5 set, not just non-empty rows).
   Define a new 5-step zone color scale (Z1→Z5, cool→warm, e.g. blue→green→yellow→orange→red)
   as a small helper (e.g. `CardioMath.zoneColor` in the app layer, or a local mapping in
   the view) since none exists. Keep the per-zone minute legend beneath the bar. Respect
   Dynamic Type / VoiceOver: label the bar with each zone's minutes and % (NFR-2).
2. **Citation swap.** Replace `tanakaMaxHR2001` at `YourWeekView.swift:163` with a
   **zone/intensity-distribution** citation. **No such citation exists** — add a new entry
   (e.g. `seilerPolarized2010` — Seiler, "What is best practice for training intensity and
   duration distribution in endurance athletes?", *Int J Sports Physiol Perform* 2010) in
   **both** `CitationRegistry` (a new `static let` + append to `all` + a `usageReasons`
   entry, enforced by `CitationIntegrityTests`) **and** `docs/CITATIONS.md`. Render it with
   `CitationLink(compact: true)`.

**Files:** `Cadence/Cadence/Features/Coach/YourWeekView.swift`,
`CadenceCore/Sources/CadenceCore/Citation.swift` (new citation + usageReasons),
`docs/CITATIONS.md`.

**Tests:** CadenceCore `CitationIntegrityTests`/`ScienceCopyTests` must stay green with the
new ID (registry ↔ CITATIONS.md in sync). UI test: with cardio present, assert the zone bar
identifier renders and the science link resolves (no raw ID visible).

---

## Phased rollout (branch + PR per phase)

Grouped so each phase is independently buildable and verifiable. Order chosen to land quick
wins first and the coach-logic changes (which share Fix 6/7 machinery) together.

| Phase | Scope | Where | Risk |
|------|-------|-------|------|
| A | Fixes 1, 5 (timestamp + This-Week refresh) | CoachDecision, SessionView, HomeView | low |
| B | Fixes 2, 3 (edit-mode rest timer, tap-to-open workout) | SessionView, HomeView, CoachDecision fact id | low |
| C | Fix 4 (tab bar inset) | RootTabView | low |
| D | Fix 8 (HR-zone bar + new citation) | YourWeekView, Citation.swift, CITATIONS.md | med (new citation) |
| E | Fixes 6 + 7 (planned exercise list + split frequency) | WeeklyPlan, CoachSession reuse, PlannedDayPreviewView, CoachSchedulePreferences, CoachPlanOptimizer/CoachDecision mirror | high (coach logic + citations) |

Phases A–D are independent (branch off `main`). Phase E is the largest and depends on
nothing but should land last; 6 and 7 share the per-focus/split machinery so ship together.

---

## Verification (end-to-end)

- **CadenceCore:** `cd CadenceCore && swift build && swift test` — all new unit tests green
  (Fixes 1, 6, 7, 8 citation integrity).
- **App build:** `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build`.
- **UI suite:** run the `CadenceUITests` plan for Fixes 2, 3, 5, 6, 8. If simulator is
  degraded (~45s launches, "no debugger version"), restart CoreSimulator
  (`killall -9 com.apple.CoreSimulator.CoreSimulatorService`) and re-run; report which
  failures are real vs environment-flaky (per CLAUDE.md dev methodology).
- **Visual (`/run`):** screenshot the tab bar (Fix 4), the Home "What you did" card and its
  navigation (Fixes 1, 3), the PLANNED (NEXT WEEK) detail (Fix 6), and the HR-zone bar
  (Fix 8) to confirm appearance.
- **Citations:** verify every changed/added coaching surface renders a tappable
  `CitationLink` and no raw IDs (Fixes 7, 8).

---

## Agentic coding handoff prompt

> **Role:** You are implementing a batch of 8 fixes in the Cladiron / Cadence iOS repo
> (`/Users/arley/github/parso-workout-ios-app`). Read `CLAUDE.md` first and follow its dev
> methodology and **Post-task checklist** exactly. Logic goes in `CadenceCore` (pure,
> `swift test`); UI is thin. Schema/model changes are **additive only**. **HARD RULE:**
> every coaching output must render tappable `CitationLink`s resolved via
> `CitationRegistry.citation(forId:)` — never raw IDs; keep `CitationRegistry.all` and
> `docs/CITATIONS.md` in sync (enforced by `CitationIntegrityTests`).
>
> **Implement the fixes in this plan file** (`/Users/arley/.claude/plans/1-i-logged-a-purrfect-bear.md`),
> phase by phase (A→E), one branch per phase. For each phase:
> 1. Implement per the "Fix N" section (root cause + fix + files are specified).
> 2. Add the automated tests named in that section (`swift test` for CadenceCore logic; UI
>    tests for navigation/rest-timer/refresh/zone-bar).
> 3. Build + test: `cd CadenceCore && swift test`, then
>    `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build`
>    and the relevant UI test. Report real vs flaky failures honestly; restart
>    CoreSimulator if launches balloon.
>
> **Then run a gap analysis before committing:** re-read every "Fix N" and the decisions
> (#3 whole-card→workout; #6 full exercise list; #7 allow splits + infer frequency from
> history). For each acceptance point, confirm the shipped code actually does it — especially:
> (a) "What you did" time uses `session.date` not `endedAt`; (b) editing a past workout
> never starts the rest timer; (c) tapping the Home card opens the session; (d) "This Week"
> updates after a date edit without relaunch; (e) a PLANNED (NEXT WEEK) strength day renders
> a full multi-exercise list; (f) a 5×/week-history user gets ~5 planned strength days on
> distinct-focus consecutive days, with cited science; (g) the HR-zone stacked bar renders
> full Z1–Z5 with a new zone-training citation (not `tanakaMaxHR2001`). Fix any gaps and
> re-run tests. Reconcile the `WeeklyPlan` vs `CoachPlanOptimizer` duplication (Fix 6) and
> record the chosen source of truth in `current_state.md`.
>
> **When green and gap-free, commit in a batch:** update `current_state.md` and README
> (user-visible changes), then commit each phase (conventional-commit messages referencing
> the fix, ending with the `Co-Authored-By: Claude Opus 4.8` trailer), merge to `main`
> ff-only, push, and monitor CI (`gh run list --branch main --limit 1`). Report the final
> commit SHA(s) and CI status.
