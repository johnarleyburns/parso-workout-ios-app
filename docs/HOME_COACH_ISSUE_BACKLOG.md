# Home and Coach: Proposed Issue Backlog

Status: proposal only. This document is a reviewable set of issue drafts; it
does not create GitHub issues or authorize implementation.

The intended product position is a private, evidence-led strength coach. The
recommendation should be easy to act on, transparent to inspect, and never a
gate on user-directed training. These issues deliberately exclude social feeds,
public profiles, leaderboards, and generic AI-chat features.

## Suggested delivery order

1. Deliver issues 1–3 as the **Today decision-flow** milestone.
2. Deliver issues 4–6 as the **weekly context and trust** milestone.
3. Field-test the core loop before starting the private adherence reflection in
   issue 7.
4. Complete the App Store screenshot refresh in issue 8 before release.

---

## 1. Today: pair the coach recommendation with a persistent self-directed start path

**Priority:** P0

### Problem

Today has a coach hero and a manual `Start Workout` hub, but their relationship
is not encoded as a product contract. A recommendation must never feel like a
gate or be visually displaced by duplicate or legacy start paths.

### Code scope

- `Cadence/Cadence/Features/Home/HomeView+DashboardContent.swift`
- `Cadence/Cadence/Features/Home/HomeTodayHeroCard.swift`
- `Cadence/Cadence/Features/Home/SelectWorkoutView.swift`
- `Cadence/Cadence/Features/Home/StartWorkoutViews.swift`
- New pure presentation type in `CadenceCore/Sources/CadenceFeatures/`

### TDD plan

1. Add a pure `TodayPrimaryActionsPresenter` in `CadenceFeatures`.
2. Write presenter tests first for these states:
   - recommendation available: coach Start is primary and self-directed Start
     remains available;
   - recovery/rest: self-directed strength and cardio choices remain available;
   - loading/no history: no misleading coach CTA, but manual Start remains
     available;
   - active workout: Resume replaces coach Start and no second start action is
     shown.
3. Render the action area from the presentation model rather than distributing
   state rules throughout SwiftUI.
4. Retain or add stable accessibility identifiers:
   - `home.recommendation.start`
   - `home.startWorkout`
   - `home.resumeWorkout`

### Acceptance criteria

- A user can start a self-directed workout from Today in every coach state.
- No coach result blocks or silently changes a user-directed session.
- There is one obvious primary workout action and one obvious manual route.
- A UI test proves both routes from seeded recommendation and recovery states.

---

## 2. Today: show the actionable “what changed” prescription before the long rationale

**Priority:** P0

### Problem

The hero presents a title, duration, exercises, and an aggregated rationale. It
should also make the practical prescription obvious: training intent, current
target, and the relevant change from last time.

### Code scope

- `CadenceCore/Sources/CadenceFeatures/TodayHeroPresenter.swift`
- `CoachSession` and recommendation-presentation types in `CadenceCore`
- `Cadence/Cadence/Features/Home/HomeTodayHeroCard.swift`
- `Cadence/Cadence/Features/Home/RecommendationRationaleView.swift`

### TDD plan

1. Introduce a pure `TodayPrescriptionPresenter`.
2. Model structured fields instead of parsing a concatenated rationale string:
   - goal/intent, such as hypertrophy, strength, or recovery;
   - duration;
   - set/exercise summary;
   - one short “why now” line;
   - optional progression delta, such as `+1 rep vs last time`;
   - optional data limitation.
3. Add unit tests that prove:
   - a strength recommendation with relevant prior history produces a
     progression line;
   - absent or invalid prior comparison omits the line;
   - cardio and recovery recommendations never receive invented lift
     progression;
   - plain historical facts need no citation, while scientific claims retain
     citation IDs.
4. Add a compact prescription row above exercise details. Keep the full,
   cited explanation in the existing “Why this workout” sheet.

### Acceptance criteria

- The home card answers what to do, how long it takes, and what is different
  without opening another screen.
- The detailed rationale remains inspectable and cited.
- Historical facts and scientific claims remain visibly and semantically
  distinct.

---

## 3. Coach: expose recommendation confidence and data sufficiency

**Priority:** P0

### Problem

The app knows when training history is sparse, stale, or adequate, but that
uncertainty is largely implicit. For an evidence-led product, calibrated
confidence is part of user trust.

### Code scope

- New `CoachRecommendationConfidencePresenter` in `CadenceFeatures`
- Coach snapshot and recommendation-input types in `CadenceCore`
- `CadenceCore/Sources/CadenceFeatures/TodayHeroPresenter.swift`
- `Cadence/Cadence/Features/Home/HomeTodayHeroCard.swift`

### TDD plan

1. Define an explainable enum:
   - `.establishingBaseline`
   - `.limitedRecentData`
   - `.personalized`
2. Calculate it exclusively from deterministic inputs: completed sessions,
   recency, relevant exercise history, and valid readiness data.
3. Write tests first:
   - zero sessions produces baseline;
   - sparse or stale history produces limited data;
   - adequate recent, relevant history produces personalized;
   - imported workouts without set detail cannot overstate confidence.
4. Render a short, non-alarmist label, for example “Still learning from your
   logs” or “Personalized from your recent training.”

### Acceptance criteria

- The app never implies high personalization without adequate relevant data.
- Confidence never suppresses a recommendation or manual choices.
- Threshold logic is unit-tested and documented in code comments.

---

## 4. Today: summarize the current week’s training intent and route to details

**Priority:** P1

### Problem

The app has weekly volume, muscle coverage, cardio credit, schedules, and coach
preferences, but Today does not clearly communicate the week’s overall goal.
The system can therefore feel reactive rather than programmatic.

### Code scope

- New `WeeklyIntentPresenter` in `CadenceFeatures`
- `Cadence/Cadence/Features/Home/HomeView+DashboardContent.swift`
- `Cadence/Cadence/Features/Home/HomeWeekDashboardSection.swift`
- `Cadence/Cadence/Features/Home/HomeRouting.swift`

### TDD plan

1. Build a pure weekly summary from existing dashboard inputs:
   - strength days completed / target;
   - cardio minutes completed / target;
   - highest-priority muscle gaps;
   - next scheduled workout, if any.
2. Write tests for an empty week, an active scheduled week, strength-only and
   cardio-only preferences, and a completed week.
3. Add one compact tappable card below the recommendation area; do not restore a
   Plan tab.
4. Route strength details to Strength and cardio details to Cardio.

### Acceptance criteria

- Today answers “what am I trying to complete this week?”
- The card has at most three summary lines.
- It does not duplicate dense dashboard content or create a second planning
  engine.
- The relevant weekly details are reachable in one tap.

---

## 5. Coach: add a plain-language evidence summary to cited recommendations

**Priority:** P1

### Problem

“The science” links are valuable, but users first need the applied takeaway:
what claim a study supports, for whom, and any material limitation.

### Code scope

- Citation model and registry in `CadenceCore`
- `Cadence/Cadence/Features/Coach/CitationDetailView.swift`
- `Cadence/Cadence/Features/Home/RecommendationRationaleView.swift`
- `CoachSourcesLink` callers

### TDD plan

1. Add presentation metadata to each coach citation:
   - `appliedClaim`;
   - `populationOrContext`;
   - optional `limitation`;
   - existing source URL and bibliographic fields.
2. Write validation tests that prove:
   - every citation used for a coach claim resolves to an evidence capsule;
   - a new coach-generated claim without one fails validation;
   - plain historical facts do not require an evidence capsule.
3. Update the rationale sheet and citation detail to show the capsule before the
   full reference.

### Acceptance criteria

- A user can understand why a source matters without reading its abstract.
- No medical, diagnostic, or certainty claims are added.
- Evidence remains connected to the particular recommendation claim, rather
  than only to a general bibliography entry.

---

## 6. Start Workout: consolidate user-directed strength entry points and preserve fast repeat workouts

**Priority:** P1

### Problem

`StartWorkoutView` → `PickWorkoutView` and `WeightsStartView` cover overlapping
concepts: suggestions, blank/custom workouts, previous workouts, and library
routines. Multiple routes risk diverging behavior and confusing users.

### Code scope

- `Cadence/Cadence/Features/Home/StartWorkoutViews.swift`
- `Cadence/Cadence/Features/Home/WeightsStartView.swift`
- `Cadence/Cadence/Features/Home/PreviousWorkoutsView.swift`
- Existing start-flow UI tests in `Cadence/CadenceUITests/`

### TDD plan

1. Inventory every live route into `WeightsStartView`, `PickWorkoutView`,
   templates, custom plans, and previous workouts.
2. Write route-contract tests:
   - Custom Workout opens an editable blank plan;
   - Previous Workout preserves exercises and editable prior targets;
   - Saved Workouts opens templates;
   - Suggest a Workout remains distinct from manual start;
   - Schedule does not begin a workout.
3. Choose one canonical user-directed strength-start surface.
4. Delete or convert unused/deprecated route code only once all route contracts
   pass.

### Acceptance criteria

- Each start intent has one name and one destination.
- Suggest, custom, previous, saved, schedule, and retrospective logging cannot
  be confused.
- Starting a repeat workout takes no more than two taps after opening Start
  Workout.

---

## 7. Progress: add a private weekly/monthly adherence reflection

**Priority:** P2

### Problem

Because Cladiron intentionally has no social model, retention should come from
self-comparison and personal follow-through—not public feeds, rankings, or
streak theater.

### Code scope

- New `AdherenceReflectionPresenter` in `CadenceFeatures`
- Progress selection and presentation code
- Home completion summary only if a small link is warranted

### TDD plan

1. Define neutral private measures:
   - completed versus intended sessions;
   - consistency versus the user’s own prior period;
   - voluntary reschedules/overrides;
   - completed strength/cardio targets.
2. Write tests first:
   - no plan/no target does not display a misleading adherence percentage;
   - planned but rescheduled workouts count correctly;
   - an unplanned manual workout contributes to consistency but not falsely to
     plan adherence;
   - data reset/import edge cases are stable.
3. Render it as reflection, for example “You trained 3 of 4 intended sessions,”
   rather than gamification.
4. Do not add public sharing, rankings, follower models, or social
   notifications.

### Acceptance criteria

- Comparisons are only to the user’s own history or stated plan.
- Missed workouts receive no punitive copy.
- Calculations are pure and fully unit-tested.

---

## 8. Marketing QA: regenerate screenshots from the current navigation flow

**Priority:** P2 / release gate

### Problem

The checked-in Home screenshot appears to show retired navigation and old quick
actions, while current code uses Today, Strength, Cardio, Progress, and Find.

### Code scope

- `Cadence/CadenceUITests/AppStoreScreenshotsUITests.swift`
- `docs/app-store/metadata.md`
- `docs/app-store/screenshots/`

### TDD / QA plan

1. Add UI assertions for current root tabs and Today’s recommendation/manual
   start surfaces.
2. Seed a deterministic recommendation and capture:
   - Today recommendation;
   - “Why this workout” evidence surface;
   - fast manual start;
   - Progress;
   - citation detail.
3. Replace retired screenshot names and copy, including
   `07-home-planning-retired`.
4. Add a release-review checklist ensuring screenshots do not refer to retired
   tabs or flows.

### Acceptance criteria

- Screenshot tests fail if retired tabs or controls return.
- Every shown screen exists in the shipping navigation model.
- App Store copy describes Today’s cited, editable recommendation rather than
  an obsolete weekly-plan flow.
