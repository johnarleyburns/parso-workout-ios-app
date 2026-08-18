# Phase 7 — Workouts Today: tappable detail, COACH'S PLAN, start a planned workout

Field-test issue #6: *"On Home View 'Workouts Today' I should be able to click on
the individual workout to see its detail, also show the detail just like on This
Week for already done exercises (with title, subtitle, number of sets, exercises,
planned volume, etc) likewise for planned cardio and allow me (if I so chose) to
start it; also don't say PLANNED say COACH'S PLAN instead if the source is from
the coach, in the future when we have self-created or trainer-created plans then
we will also say 'YOUR PLAN'."*

Depends on **Phase 1** (button metrics) and **Phase 6** (HomeView LOC headroom).

## 1. What the code does today

`Home/HomeView.swift:587-634` `workoutsTodaySection` renders three flat,
**non-interactive** `HStack`s:
- completed strength → `✓ <title> … COMPLETED`
- completed cardio → `✓ <title> … COMPLETED`
- `coachDecision.todayPlannedRecommendations.filter { $0.kind != .rest }`
  → `📅 <title> … PLANNED`

No detail, no tap target, no way to start the planned item, and the literal word
`PLANNED`.

Meanwhile the **This Week** card already has exactly the row the user wants:
`HomeWeekWorkoutRow` (`Home/HomeWhatYouDidRow.swift`) rendering
`TodayActivityPresenter.Entry` (`title`, `detail` = exercise names,
`value` = "5 sets · 42m") with a chevron and an `onOpen` action.

## 2. Design

```
Workouts Today
┌──────────────────────────────────────────────────────┐
│ 🏋️ Push Day                       5 sets · 42m   ›   │  COMPLETED (green)
│    Bench Press, Overhead Press, Dips                  │
│ ────────────────────────────────────────────────────  │
│ ❤️ 132 bpm · Cardio               5.2 km · 31m   ›   │  COMPLETED (green)
│ ────────────────────────────────────────────────────  │
│ 📅 Upper body — push emphasis     12 sets · ~45m  ⌄  │  COACH'S PLAN (teal)
│    Bench Press, Overhead Press, Triceps Pushdown      │
└──────────────────────────────────────────────────────┘

planned row expanded:
┌──────────────────────────────────────────────────────┐
│ 📅 Upper body — push emphasis     12 sets · ~45m  ⌃  │  COACH'S PLAN
│    Closes this week's chest deficit.                  │  ← subtitle
│    Bench Press          3 × 12,10,8      45 kg        │
│    Overhead Press       3 × 12,10,8      30 kg        │
│    Triceps Pushdown     3 × 15,12,10     25 kg        │
│    Planned volume  4,860 kg                           │
│    The science ›                                      │
│  ┌────────────────────────────────────────────────┐   │
│  │  ▶  Start This Workout                         │   │  56 pt full width
│  └────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

- **Completed** rows: tap navigates, exactly like This Week —
  `path.append(session)` / `path.append(cardio)` via the existing
  `openWeekWorkout(_:)` logic. Reuse `HomeWeekWorkoutRow` verbatim so the two
  cards are visually identical (the user asked for "just like on This Week").
- **Planned** rows: tap **expands in place** (there is nothing to navigate to
  yet), revealing the subtitle, per-exercise prescription, planned volume, the
  single science link, and a full-width `Start This Workout` action.
- Planned **cardio** expands to modality, target duration, target intensity/zone,
  and the same start action.
- Badge text comes from `PlanSource` (decision **D10**): `COACH'S PLAN` /
  `YOUR PLAN` / `TRAINER'S PLAN`. Only `.coach` is produced today.
- Starting a planned item calls the existing `launchDecision(_:)`, which routes
  through `CoachRouter` to the plan editor / cardio setup — never straight into a
  recorder (NFR-8 and the audio/coach routing rule).

## 3. Presenter — new `CadenceCore/Sources/CadenceFeatures/WorkoutsTodayPresenter.swift`

```swift
import Foundation
import CadenceCore

/// Home's "Workouts Today" list: today's completed workouts plus the coach plan
/// still outstanding, as one ordered, renderable model. Pure so the badge
/// vocabulary, the ordering and the planned-volume arithmetic are unit-tested.
public enum WorkoutsTodayPresenter {

    /// Who authored a planned session. Only `.coach` is produced today; `.user`
    /// and `.trainer` exist so the badge needs no re-plumbing when self-created
    /// and trainer plans land (Cladiron Platform Spec v2.2).
    public enum PlanSource: String, Equatable, Sendable {
        case coach, user, trainer
        public var badgeText: String {
            switch self {
            case .coach: "COACH'S PLAN"
            case .user: "YOUR PLAN"
            case .trainer: "TRAINER'S PLAN"
            }
        }
    }

    public enum Status: Equatable, Sendable {
        case completed
        case planned(PlanSource)
        public var badgeText: String {
            switch self {
            case .completed: "COMPLETED"
            case .planned(let s): s.badgeText
            }
        }
    }

    public enum Modality: Equatable, Sendable { case strength, cardio }

    /// One prescribed exercise inside an expanded planned row.
    public struct PlannedExerciseRow: Equatable, Sendable, Identifiable {
        public let name: String
        public let sets: Int
        public let repsText: String        // "12, 10, 8" or "8–12"
        public let loadKg: Double?         // nil ⇒ bodyweight or unknown (P3 rules)
        public let isBodyweight: Bool
        public var id: String { name }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public let id: String
        public let status: Status
        public let modality: Modality
        public let title: String
        /// Second line when collapsed — exercise names, or the cardio modality.
        public let subtitle: String?
        /// Trailing value — "5 sets · 42m", "5.2 km · 31m", "12 sets · ~45m".
        public let value: String
        /// Expanded detail (planned rows only).
        public let why: String?
        public let exercises: [PlannedExerciseRow]
        public let plannedVolumeKg: Double?
        public let targetMinutes: Int?
        public let citationIds: [String]
        /// Navigation/launch key: the source workout id (completed) or the
        /// CoachSession id (planned).
        public let sourceKey: String
        public var isExpandable: Bool { status != .completed }
        public var isNavigable: Bool { status == .completed }
    }

    /// Completed first (newest first), then outstanding plan items in plan order.
    public static func rows(sessions: [WorkoutSession],
                            cardio: [CardioWorkout],
                            plannedToday: [CoachSession],
                            source: PlanSource = .coach,
                            now: Date = Date(),
                            calendar: Calendar = .current) -> [Row]

    /// Σ sets × reps × load over the prescription. nil when no exercise carries a
    /// load (a pure bodyweight plan has no meaningful tonnage).
    public static func plannedVolumeKg(_ session: CoachSession) -> Double?

    /// "12 sets · ~45m" for a planned strength session; "~30m easy" for cardio.
    public static func plannedValueText(_ session: CoachSession) -> String
}
```

Implementation notes:
- Completed rows reuse `TodayActivityPresenter.entries(sessions:cardio:now:)`
  verbatim — do **not** re-implement its filtering (`deletedAt == nil`,
  `!isResumable`, `endedAt != nil`, today's date window) or its `value`
  formatting. Map its `Entry` into `Row`.
- Planned rows come from `CoachDecision.todayPlannedRecommendations`, already
  filtered by the caller to `kind != .rest`.
- `repsText`: `repLadder` joined by `", "` when present, else
  `"\(repsLow)–\(repsHigh)"`, else `"\(repsLow)"`.
- `isBodyweight` uses `ExerciseLoading.isBodyweight(named:)` from Phase 3.
- `plannedVolumeKg` sums `Σ over exercises Σ over ladder (reps × loadKg)`;
  exercises with `loadKg == nil` contribute 0; return `nil` if the total is 0.

## 4. View — new `Cadence/Cadence/Features/Home/HomeWorkoutsTodaySection.swift`

`HomeView.swift` is at its LOC ratchet; extract the whole section.

```swift
struct HomeWorkoutsTodaySection: View {
    let rows: [WorkoutsTodayPresenter.Row]
    @Binding var expandedRowIDs: Set<String>
    let onOpenCompleted: (WorkoutsTodayPresenter.Row) -> Void
    let onStartPlanned: (WorkoutsTodayPresenter.Row) -> Void
}
```
- Card chrome identical to today: `.padding(LayoutMetrics.cardPadding)` +
  `.cadenceGlassCard(corner 16, tint: .green)` + id `home.workoutsToday`.
- Completed rows: reuse `HomeWeekWorkoutRow` (add an optional `badge: String?`
  parameter to it so it can show `COMPLETED`, defaulting to nil so This Week is
  unchanged).
- Planned rows: a new `HomePlannedWorkoutRow` inside the same file — collapsed
  header (icon, title, subtitle, value, badge, chevron) + expanded detail +
  `CadenceActionButton("Start This Workout", systemImage: "play.fill")`.
- Ids: `home.today.row.<sourceKey>`, `home.today.badge.<sourceKey>`,
  `home.today.start.<sourceKey>`, `home.today.science.<sourceKey>`.
  Keep `home.workoutsToday` on the card.
- `.accessibilityElement(children: .contain)` on the card before its identifier.
- `.contentShape(Rectangle())` on every row button (Spacer gotcha).

`HomeView` keeps only the wiring:
```swift
HomeWorkoutsTodaySection(
    rows: workoutsTodayRows,
    expandedRowIDs: $expandedTodayRowIDs,
    onOpenCompleted: openTodayWorkout,
    onStartPlanned: startPlannedToday)
```
with
```swift
private func startPlannedToday(_ row: WorkoutsTodayPresenter.Row) {
    guard let session = coachDecision.todayPlannedRecommendations
        .first(where: { $0.id == row.sourceKey }) else { return }
    Haptics.selection()
    launchDecision(session)
}
```

## 5. Tests

### New — `CadenceCore/Tests/CadenceFeaturesTests/WorkoutsTodayPresenterTests.swift`
```
testCompletedRowsComeFirstNewestFirst
testPlannedRowsFollowInPlanOrder
testPlannedBadgeSaysCoachsPlanForCoachSource
testPlannedBadgeSaysYourPlanForUserSource
testPlannedBadgeSaysTrainersPlanForTrainerSource
testCompletedBadgeSaysCompleted
testNoRowsWhenNothingCompletedOrPlanned
testDeletedSessionsAreExcluded
testInProgressSessionIsNotCompleted            // isResumable
testPartialTwoADayKeepsTheOutstandingPlanVisible
testStrengthSubtitleListsExerciseNames
testCardioRowCarriesDistanceAndDuration
testPlannedExerciseRowsCarrySetsRepsAndLoad
testPlannedRepsTextUsesTheLadderWhenPresent
testPlannedRepsTextFallsBackToTheRepRange
testPlannedVolumeSumsSetsRepsTimesLoad
testPlannedVolumeIsNilForAPureBodyweightPlan
testBodyweightExerciseIsFlaggedNotZeroLoaded
testPlannedValueTextForStrengthAndForCardio
testCompletedRowsAreNavigableAndPlannedRowsAreExpandable
testPlannedRowCarriesTheSessionCitationIds
```

### `CadenceCore/Tests/CadenceFeaturesTests/TodayActivityPresenterTests.swift`
Re-run; unchanged behaviour (we consume it, we don't modify it).

### UI smoke — inside the single existing test
```swift
// Field test 2026-08-18 #6: Workouts Today rows carry a plan-source badge.
XCTAssertTrue(app.descendants(matching: .any)["home.workoutsToday"].waitForExistence(timeout: 10),
              "Workouts Today card is missing")
XCTAssertFalse(app.staticTexts["PLANNED"].exists,
               "Workouts Today still uses the bare PLANNED badge")
```
and, after the workout completes and Home returns, assert the just-finished
session appears as a tappable row:
```swift
let todayRow = app.descendants(matching: .any)
    .matching(NSPredicate(format: "identifier BEGINSWITH 'home.today.row.'")).firstMatch
XCTAssertTrue(todayRow.waitForExistence(timeout: 10),
              "Completed workout did not appear in Workouts Today")
```

## 6. Acceptance criteria

- [ ] Every Workouts Today row is interactive.
- [ ] A completed strength/cardio row shows title, exercise-name subtitle, and
      `N sets · duration` / `distance · duration`, and tapping it opens the same
      destination This Week opens.
- [ ] A planned row expands in place to show: why, each exercise with sets ×
      reps × load, planned volume, one science link, and a full-width
      `Start This Workout` button.
- [ ] Planned cardio expands to modality + target duration and can be started.
- [ ] The badge reads `COACH'S PLAN` — the literal string `PLANNED` no longer
      appears anywhere in `Cadence/Cadence/Features`
      (`grep -rn '"PLANNED"' Cadence/Cadence/Features` is empty).
- [ ] Starting a planned item routes to its setup surface (plan editor / cardio
      setup), never directly into a recorder.
- [ ] Partial two-a-days still show the outstanding component (existing behaviour
      preserved).
- [ ] `HomeView.swift` shrank again; the ratchet entry was lowered.
- [ ] `HomeWorkoutsTodaySection.swift` ≤ 400 LOC.
- [ ] `make ci` green; `make smoke` green.

## 7. Commit

```
feat: Workouts Today rows open, expand and start

Field test 2026-08-18 #6. Completed rows now carry This Week's detail and
navigate; coach-planned rows expand to sets/reps/load/volume with a full-width
Start This Workout action; the badge says COACH'S PLAN, with YOUR PLAN and
TRAINER'S PLAN already modelled for self- and trainer-authored plans.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

Update `current_status.md`, commit, **do not push**, report, stop.
