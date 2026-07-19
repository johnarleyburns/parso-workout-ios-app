# Field-test fixes + launch-blocker completion — test-first plan

Date: 2026-07-18. Companion files: `decisions.md` (settled owner decisions), `HANDOFF.md`
(paste-ready implementing prompt), `current_state.md` (updated per phase).

## Context

Three inputs converge here:

1. **Verification of the launch-blockers plan** (`plans/launch-blockers/2026-07-18/00-plan.md`):
   Phases 1–2 shipped (`634824e`, `9233975`, tests green, tree clean). Phase 2 Step 6
   (Your Plan cached facts) was deferred; **Phases 3–5 were never started** (no commits, no
   branches, planned files absent). `current_state.md` was never created.
2. **Field-testing bug report (2026-07-18)** — four coach/Home bugs, diagnosed below against
   the owner's export (`~/Downloads/Cladiron-Export-2026-07-18.json.gz`).
3. **Editing bugs re-reported**: Swap does nothing after picking a replacement; no way to
   delete an exercise from a completed workout.

## Protocol (owner requirement — "mathematically correct")

Every bug gets a headless `swift test` that:
- (a) **FAILS on current code, proving the bug is real** — run it, record the failure output;
- (b) **passes after the fix** — the plan is complete only when ALL new tests pass alongside
  the existing suite (1184 at time of writing).

All logic lands in `CadenceCore`/`CadenceFeatures` so no simulator or user interaction is
needed to verify. **No new XCUITests** (test-pyramid rule; smoke suite stays ≤12).

## MANDATORY per-phase ship gate

**Each phase must be fully shipped before the next phase starts.** At the end of every phase,
in order — no exceptions, no batching phases into one commit:

1. `cd CadenceCore && swift test` — fully green (new tests included).
2. `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build` — green.
3. `scripts/check-test-pyramid.sh` passes (import ban, ≤12 UI tests, LOC budgets —
   SessionView ratchet ≤1102 must hold after Phase E edits).
4. Update `plans/field-test-fixes/2026-07-18/current_state.md` with what shipped + new test counts.
5. Stage + commit with a conventional message referencing this plan (e.g.
   `fix(coach): never-block active-workout gate + resume truth (field-test A)`), ending with
   the `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer.
6. Merge to `main` (`git checkout main && git merge --ff-only <branch>` if on a branch).
7. `git push origin main`.
8. **Check CI and wait for green**: `gh run list --branch main --limit 1`, then
   `gh run watch <id>` (or poll) until the workflow succeeds. If CI fails, fix on the same
   phase before proceeding.
9. Only then begin the next phase.

Branching: one branch per phase per repo methodology (A: `fix/active-session-truth`, then
B/C stacked on A since their tests assume A's gate semantics; D/E/F/G independent off `main`).
Committing directly to `main` per phase is acceptable if the owner prefers — the gate above
still applies verbatim.

## Diagnosis (verified against the export)

The export shows **exactly one session with `endedAt: null`**: this morning's "Strength focus"
(started 15:24Z, 23 sets across 6 exercises, last set 15:57Z, `isLogged: false`, 8 planned
exercises of which 2 were never performed). Schedule prefs: strength 5×/wk, cardio 6×/wk,
two-a-days on, fixed rest = Sunday. This week: 3 completed strength days + 5 cardio days.

| Symptom | Root cause |
|---|---|
| "A workout is currently in progress. Finish or discard it first." with no visible active workout | The stranded `endedAt == nil` session. Coach reads persisted `endedAt` (`TrainingEvent.swift:157` → `SessionEligibilityPolicy.swift:37-41` defers **every** candidate); the Resume card reads only in-memory `ActiveWorkoutModel.strengthSession` (`HomeView.swift:290`). Two sources of truth diverge. |
| "Strength is done today" + "Air Squat and Air Squat logged" | `CoachDecisionCardView.swift:370-432`: hero copy is built from **deferred planned candidates**, not logged work — `recentlyTrainedExercises()` maps each deferred strength candidate's *first planned exercise* with no dedup. Both candidates lead with `preferred[.squat]`, which is "Air Squat" (the user's only squat-pattern lift in the rolling 28d window — 4 sets on Jul 4). Nothing there was "logged". |
| "Take a Rest Day" instead of due cardio | All candidates deferred (above) → `eligible` empty → `CoachDecision.swift:198-221` fallback rescues only **strength** (`strengthNeeded`); there is no cardio-need rescue and `restPreference` is never consulted → `rest.fallback` wins over still-due scheduled cardio. NFR-8 violation. |
| Morning workout missing from "What you did" | `HomeView.swift:721-726` renders `coachDecision.observedFacts` (≤1 strength + ≤1 cardio, **completed events only** — `CoachFacts.swift:234`). The stranded in-progress session is excluded; a second same-day session would be too. |
| Swap picks but doesn't swap | `ExercisePickerView` detail-drill path calls `dismiss()` **before** `onPick(picked)` (`:263-265`); dismissal nils `swappingPlannedName`/`changingExerciseFor` via the derived `isPresented` bindings (`SessionView.swift:395-417`), so the handler's `if let` fails silently. Row taps work (`onPick; dismiss`). |
| No delete-exercise on completed workout | `plannedCard` (`SessionView.swift:649+`) has only info/Swap/Add Set — no Remove. (Cards **with** sets do have Remove via the ellipsis menu in `ExerciseCardView.swift:99-104`.) Leftover planned-only exercises on a finished workout are undeletable. |

No data surgery needed: once Phase A ships, the stranded session surfaces as a Resume card;
finishing it resolves the cascade naturally.

---

## Phase A — One source of truth for "in progress" + never-block gate

Per owner decision (`decisions.md` #1): **the coach never blocks on an in-progress workout,
it only warns.**

1. **`CadenceCore` (`Models.swift` or small extension file)**: add `WorkoutSession.isResumable`
   — `endedAt == nil && deletedAt == nil && !isLogged`. Refactor `ActiveSessionRecovery.candidate`
   (`CadenceFeatures/ActiveSessionRecovery.swift:12-16`) to use it — one predicate everywhere.
2. **`SessionEligibilityPolicy.swift:37-41`**: delete the active-workout **defer**. Instead,
   `CoachDecisionEngine.run` attaches a **warning** (`DecisionReason(id: "activeWorkout", …)`,
   `citationIds: []` — observation, not a science claim, matching existing precedent) when an
   in-progress event exists. Candidates stay eligible.
3. **`HomeView.swift:290`**: Resume card renders when `active.strengthSession != nil` **or**
   `ActiveSessionRecovery.candidate(in: sessions)` exists; tapping the persisted-candidate card
   calls `active.adopt(candidate, heartbeat:)` then `active.present()`. (Reuses the adopt path
   from `RootTabView.swift:146-154` — mid-session stranding no longer needs an app relaunch to
   become visible.)

**Proof tests (fail first):**
- `SessionEligibilityPolicyTests`: facts with an in-progress event → currently defers with
  `"activeWorkout"`; new assertion: candidates remain eligible, decision carries the warning.
- New invariant test (`CadenceFeaturesTests`): for any session set, *coach sees in-progress*
  ⟺ *a resume affordance exists*. Current code fails with an `isLogged: true, endedAt: nil`
  fixture (coach blocks, `candidate` filters it out).

**Ship gate (steps 1–9 above) before Phase B.**

## Phase B — Coach hero copy from logged work, not planned candidates

1. New **`CadenceFeatures/CoachHeroPresenter.swift`**: extract `heroTitle`/`heroSubtitle`
   logic out of `CoachDecisionCardView.swift:370-432` into a pure function over
   (`CoachDecision`, facts-derived inputs) returning a semantic struct; the view just renders it.
2. Correct semantics: "Strength is done today" **only if** a strength event was actually
   completed today (`facts.todayCompletedEvents`); "… logged" names come from that event's
   **logged** exercise names — deduped, ≤3; deferred candidates' planned exercises never appear
   as "logged".

**Proof tests (fail first):** fixture with two deferred strength candidates both leading with
"Air Squat" and **no** strength completed today → behavior-preserving port initially reproduces
"Air Squat and Air Squat logged" (the failing assertion), corrected presenter emits neither the
duplicate nor "done today". Second test: completed session today (Snatch, Lat Pulldown, Snatch)
→ "Snatch and Lat Pulldown logged".

**Ship gate before Phase C.**

## Phase C — Decision fallback honors the schedule (NFR-8)

`CoachDecision.swift:198-221`: extend the empty-`eligible` rescue — after the existing strength
override, if the weekly **cardio** target is unmet (`weeklyBalance` vs
`schedulePreferences.cardioDaysPerWeek` / aerobic minutes), rescue the best deferred cardio
candidate (with its advice note) before ever falling back to rest. `rest.fallback` remains only
when all stated targets are met (or it's the user's stated rest day).

**Proof tests (fail first):** fixture mirroring the export — strength 5/wk (3 done), cardio
6/wk (5 done), two-a-days, fixed Sunday rest, today Saturday, all candidates deferred by a
recovery gate → currently `primary.id == "rest.fallback"`; assert primary (or todayPlanned)
is a cardio session, never rest. Companion: same facts on Sunday (stated rest day) → rest is
fine. Citations: rescued sessions carry their existing engine citations; no new science claims.

**Ship gate before Phase D.**

## Phase D — "What you did" = true today-list (launch-blockers Phase 5, as specced)

Implement Phase 5 exactly as written (`plans/launch-blockers/2026-07-18/00-plan.md:130-136`):
new **`CadenceFeatures/TodayActivityPresenter.swift`** —
`entries(sessions:cardio:unit:now:calendar:)`, same calendar day, completed ⇔ `endedAt != nil`,
`deletedAt == nil`, resumable session excluded (the Resume card covers it — Phase A guarantees
that card exists), no cap, newest first. `HomeView` replaces `whatYouDidFacts` (`:721-726`) +
row rendering with the presenter over its existing `@Query` arrays. Empty copy:
"Nothing yet today."

**Proof tests:** the 8 specced presenter tests (includesOnlyToday, inProgressExcluded,
deletedExcluded, multipleSameDayAllListed, mixedSortedNewestFirst, midnightBoundary,
unitFormatting, emptyDay) + one documenting the old source's defect (engine `observedFacts`
yields ≤1 strength entry for two completed-today sessions) + the joint invariant: every
non-deleted today session appears exactly once across Resume-card ∪ today-list.

**Ship gate before Phase E.**

## Phase E — Swap + remove exercise while editing (launch-blockers Phase 3 + delete gap)

1. New **`CadenceFeatures/ExerciseSwap.swift`**:
   `enum SwapTarget: Identifiable { case planned(name: String); case logged(exerciseID: UUID) }`
   plus pure apply-logic. `SessionView` replaces the two derived-`isPresented` sheets
   (`:395-417`) with **one `.sheet(item: $swapTarget)`** — the payload rides the item and can
   never be nilled by dismissal.
2. **`ExercisePickerView.swift:263-265`**: reorder the detail-path to `onPick(picked); dismiss()`
   (matching the row path).
3. **`plannedCard`** (`SessionView.swift:649+`): replace the lone Swap button with the same
   ellipsis Menu as `ExerciseCardView` — Swap + **Remove** (destructive). Remove planned =
   drop the name from `plannedExerciseNames`. Works on completed (`endedAt != nil`) workouts.
4. Move remove-exercise-with-sets logic (`SessionView.swift:522-528`) into
   **`WorkoutRepository.removeExercise(_:from:in:)`**; planned-name removal into
   `WorkoutRepository.removePlannedExercise(named:from:in:)`.

**Proof tests:** (a) a test replicating the old handler contract — payload read from optional
state that dismissal nils → no-op (documents the failure mode); the item-based handler takes
the payload as an argument and cannot fail that way. (b) `changeExercise` moves sets + dedups
planned names. (c) `removePlannedExercise` removes exactly that card's name.
(d) `removeExercise` deletes the exercise's sets and its planned name, on a session with
`endedAt != nil`.

**Ship gate before Phase F.**

## Phase F — HomeView "Your Plan" uses cached coach facts (deferred launch-blockers Phase 2 Step 6)

`CoachSnapshotBuilder.build` already computes the exact `CoachFacts` YourWeekView needs
(`CoachSnapshotBuilder.swift:60`) but discards it (`TrainingFacts` ≠ `CoachFacts`; not
convertible — the mismatch that caused the deferral).

1. **`CoachSnapshotBuilder.swift`**: add `public let coachFacts: CoachFacts` to `CoachSnapshot`
   (only the builder constructs it — verified); return the line-60 value.
2. **`CoachFacts.swift`**: add `func withStepSummary(from activityTrend: [DayActivity]) -> CoachFacts`;
   refactor the `make(..., activityTrend:)` overload (`:291-322`) to use it. Overlaying at the
   call site (a 7-element array wrap) deliberately avoids threading `activityTrend` into the
   builder — raw step counts in `HomeCoachModel.Signature` would re-run the whole pipeline on
   every HealthKit refresh.
3. **`HomeCoachSnapshot.swift`**: mirror `coachFacts`.
4. **`HomeView.swift`**: `.yourPlan` (`:349-357`) and `strengthAnyway()` (`:1048-1053`) become
   `coachSnapshot.coachFacts.withStepSummary(from: activityTrend)`; delete now-unused
   `buildTrainingEvents()` (`:263`).

**Tests:** `CoachSnapshotBuilderTests` assert `coachFacts` exposed and consistent
(`readiness == snapshot.readiness`, goal/events match); `CoachFactsTests` assert
`withStepSummary` populates `stepSummary` preserving all other fields.

**Ship gate before Phase G.**

## Phase G — Per-rep-count weight auto-fill + e1RM fallback (launch-blockers Phase 4)

Implement launch-blockers Phase 4 as specced (`plans/launch-blockers/2026-07-18/00-plan.md:116-128`),
adjusted for the Phase-2 refactor that has since landed (the inline editor is now the extracted
`InlineSetEditorView` fed by `InlineEditorConfig` — which already carries `priorWeightHint`,
built in `SessionView.inlineEditorConfig()`):

1. **New CadenceCore `WeightSuggestion.swift`**: `suggest(targetReps:history:formula:) -> Result?`
   — `weightKg` (raw entered kg, preserving dumbbell/barbell semantics), `basis`
   (`.exactRepMatch` / `.estimatedFromE1RM`), `citationIds` (non-empty for e1RM: reuse the
   existing **`oneRMEstimation`** registry id — verified present). Inverse formulas: Epley
   `w = e1RM/(1 + r/30)`; Brzycki `w = e1RM × (1.0278 − 0.0278r)` via `settings.formula`.
   Rules: most-recent exact-rep set wins → e1RM from most recent best working set → nil
   (view falls through to the existing cascade).
2. **New accessor** `WorkoutRepository.performerSetHistory(for:performedBy:excluding:)`
   (mirrors `repLadderHistory`): raw-weight, non-warmup, per-performer, newest first. Confirm
   `SetSample` carries raw weight+reps+date (add a raw-weight init path if it only has
   effective load — still no schema change).
3. **Cascade integration** (new `CadenceFeatures/InlineEditorDefaults.swift` or extend
   `SessionViewModel`): `defaultWeight(targetReps:currentSessionSets:performerID:priorHistory:formula:prescribedKg:isPrescribed:)`;
   precedence current-session-exact-rep → `WeightSuggestion` → existing cascade. Feed through
   `InlineEditorConfig` per performer — no fetch on tap. Changing reps before touching weight
   re-computes the prefill.
4. **Citation hard rule**: update the `oneRMEstimation` usage note + `docs/CITATIONS.md` entry
   for the new surface; the hint in `InlineSetEditorView` replaces the current
   `priorWeightHint` copy: exact match → "Last time at N reps: X"; e1RM → "Suggested from your
   best recent set" + `CitationLink(compact: true)`. `everyEmittedCitationIdResolves` must fail
   the build if the id ever leaves the registry.

**Proof tests:** the specced suite — exactRepMatchWins, mostRecentExactMatchPreferred,
e1RMScalesFromBestRecentSet (numeric inverse-Epley), e1RMUsesChosenFormula, warmupsExcluded,
**partnerHistoryFullySeparated**, roundTripSelfConsistency, noHistoryReturnsNil; cascade:
currentSessionExactRepBeatsPrior, fallsThroughToPrescribedLoad,
unitConversionViaCanonicalKgRoundTrips; repo: performerSetHistoryFiltersWarmupsAndPerformer
(in-memory container). ("Fail first" here = the new suite fails to compile/pass until the
feature exists; the defect being proven is the absent capability, not a wrong branch.)

**Acceptance:** an 8-rep row prefills the last 8-rep weight for that performer; only-5-rep
history prefills the inverse-Epley estimate **with a visible tappable citation**; empty history
behaves exactly as today.

**Ship gate — final.** After Phase G's CI is green, do the closing pass: audit this plan vs
implementation, finalize `current_state.md`, update README if user-visible behavior changed,
and report all phase SHAs + CI statuses.

---

## Out of scope, explicitly deferred

- The decision-engine step-count observation (`CoachDecision.swift:321` never fires on Home
  because builder facts lack step data) — separate follow-up.

## End-to-end verification (owner-assisted, on device)

After updating: Home shows a Resume card for the stranded "Strength focus" workout → finish it
→ hero copy correct, cardio button present, workout listed in "What you did"; swap + remove
exercise work on a completed workout; the inline set editor prefills per-rep weights (with a
tappable citation when estimated from e1RM).

With Phase G included, every remaining launch-blocker item is covered by this plan:
Phase 3 → E, Phase 4 → G, Phase 5 → D, Phase 2 Step 6 → F.
