# Decisions — field-test UI batch 2026-08-18

Settled during planning. **Do not re-litigate.** If the code contradicts one of
these, the code is wrong.

### D1 — Commit directly to `main`, one commit per phase, never push
The user reviews each phase before the next begins and explicitly asked for
"committing (but not pushing) after each phase". A branch would add a merge step
with no review benefit, since nothing leaves the machine until the user pushes.
CLAUDE.md's post-task checklist steps 6–8 (push + CI monitoring) are **suspended
for this batch** by the user's explicit instruction.

### D2 — One canonical full-width action button
Home's `Start Workout` is the reference control: `.borderedProminent`, `.green`
tint, `.font(.headline)`, `frame(maxWidth: .infinity, minHeight: 52)`. Every
other primary full-width action (`Quick Start`, `Custom Workout`,
`Coach's Workout`, `Start Workout` in the plan editor, `Do Coach's Workout`)
adopts the **same height and typography**. Secondary actions
(`Log Previous Workout`) keep `.bordered` but the identical metrics.
The gradient/glass hero treatment used today by `SelectWorkoutView` and
`WeightsStartView` is kept as the *fill*, but its geometry is normalized — the
user asked for equal heights, not a visual rewrite.

### D3 — Layout constants live in `CadenceFeatures`, not in the view
`LayoutMetrics` is a plain `Double`-valued enum in
`CadenceCore/Sources/CadenceFeatures/LayoutMetrics.swift` so a `swift test` can
assert the four buttons share one height and the three surfaces share one
spacing. The app maps `Double` → `CGFloat` at the call site. This keeps the
test-pyramid guard happy (no SwiftUI in CadenceFeatures) and makes "same height"
a *tested* property rather than a visual claim.

### D4 — `BW` is a statement about the movement, not about missing data
After P3, `CompactExerciseRow` (and any other planned-set renderer) shows `BW`
**only** when `ExerciseLoading.isBodyweight(named:)` is true. A loaded movement
with no resolvable history renders `—` (em dash) with the reps, never `BW`.
Inventing a weight for a movement the user has never logged is out of scope and
would be a fabricated prescription.

### D5 — Load resolution order for a coach-planned exercise
1. `CoachSession.RecommendedExercise.loadKg` if already set.
2. `TrainingFacts.liftSnapshots` exact (case-insensitive) name match — the
   trailing-week top set (unchanged, keeps existing tests green).
3. **New:** the user's most recent matching `StrengthEventDetails.PerExercise`
   across `CoachFacts.events`, matched by `MuscleCatalog.canonicalName`, scaled
   with `WeightSuggestion.inverseE1RM` to the planned rep target.
4. Bodyweight movement → `nil` (correct, renders `BW`).
5. Otherwise → `nil` (renders `—`).

### D6 — Summary exercise expansion replaces the separate Partners section
Issue 1 asks for one row per performer *inside* the exercise detail. Keeping the
old bottom `Partners` roll-up as well would show the same numbers twice.
The `partnersSection` in `WorkoutSummaryView` is therefore **removed** and its
information moves into the expanded exercise rows. `WorkoutSummaryData.partners`
stays in the value type (export/back-compat, and other callers), it is simply no
longer rendered as its own section.

### D7 — Tapping an exercise in the summary expands, it never navigates
Today the summary's exercise row pushes `SessionView` (the editor). After P4 the
row toggles an inline, read-only disclosure. Editing stays reachable **only**
through the existing `Edit` toolbar button, which still pushes `SessionView`.
The `HistorySummaryRoute.strengthFocused` route is kept (it is used from
Progress) but the summary no longer originates it.

### D8 — Abbreviated set format
`"<weight><unit> x <reps>"` joined by `", "` — e.g. `180 lb x 12, 190 lb x 10,
200 lb x 8`. Weight uses `Format.weight(_:unit:decimals: 0)`. Bodyweight sets
render `BW x 12`; bodyweight + added load renders `BW + 10 lb x 12`. The literal
separator is a lowercase `x` (matching the user's wording), not `×`.

### D9 — One science row, many sources
A new `CoachSourcesLink(citationIds:)` renders exactly one
`The science ›` row regardless of how many ids it is given, and pushes
`CoachSourcesView`, which lists every source vertically in a scrollable `List`
(re-using `CitationDetailView`'s presentation per source, with `How this applies`
context per id when supplied). `CitationLink` itself is unchanged for the
genuinely single-citation call sites.

### D10 — Plan-source vocabulary
`PlanSource` is a three-case enum today: `.coach` → badge `COACH'S PLAN`,
`.user` → `YOUR PLAN`, `.trainer` → `TRAINER'S PLAN`. Only `.coach` is
producible in this release; `.user`/`.trainer` exist so the badge does not need
re-plumbing when self-created and trainer plans land (Cladiron Platform Spec
v2.2). Never render the bare word `PLANNED` again.

### D11 — Partner plans are per-performer prescriptions, stored additively
`WorkoutSession` gains **one** new stored property,
`plannedPerformerPrescriptionsData: String = ""` (JSON, defaulted, CloudKit-safe)
holding `[PlannedPerformerPrescription]` keyed by the performer's `UUID` string
(`nil`/absent ⇒ the owner). Existing `plannedPrescriptions` remains the owner's
prescription and the fallback for any performer with no entry, so every legacy
session and every older JSON export keeps working untouched.

### D12 — A partner is coached only on the owner's exercises
Per the field-test wording ("so they can work in with me on sets"): the partner's
plan always has **the same exercise list and the same set count** as the owner's.
Only reps and weight are personalized, from that partner's own history. The coach
never adds or removes exercises for a partner.

### D13 — Partner personalization is history-driven, never invented
Resolution order per partner per exercise (mirrors `SessionRenderModel`):
1. that partner's most recent logged sets for **this exact exercise** →
   their ladder + their first working weight;
2. else that partner's **general rep pattern** for the exercise
   (`WorkoutRepository.repLadderHistory`) with weight `nil`;
3. else the owner's planned reps with weight `nil`.
No partner ever inherits the owner's weight.

### D14 — Vertical rhythm is Home's rhythm
Home's numbers are the standard: **20 pt** between top-level sections, **16 pt**
page padding, **12 pt** between rows inside a card, **10 pt** between a card's
heading and its first row. `WorkoutPlanEditor`'s `List` is converted to a
`ScrollView` + `VStack(spacing: 20)` of glass cards so it can actually honour
that rhythm — a `List` cannot (it owns its own row insets).

### D15 — Scope boundary
This batch is UI/coaching-correctness only. It does **not** touch: CloudKit
mirroring, WatchConnectivity, monetization/entitlements, HealthKit, or the
Cladiron Platform Spec v2.2 roadmap work (trainer mode, macOS, iPad). Any
temptation to "also fix" those is out of scope — note it and move on.
