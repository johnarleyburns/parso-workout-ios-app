# Phase 9 — Partner-aware Workout Plan (coach fills each partner's plan)

Field-test issue #4: *"on Coach's suggested workout Workout Plan view, I EXPECT I
should be able to add training partners and the workout plan should be default
filled out for the training partner as well as myself (if partner has existing
workout history, coach for them individually BUT only for my exercises (so they
can work in with me on sets), AND customize for their weight/rep history, their
history as 'implied' preferences."*

Depends on **Phase 2** (the editor's ScrollView rewrite + its extracted files) and
**Phase 3** (resolved owner loads). This is the largest phase — budget it alone.

## 1. What exists today (do not re-derive)

**Already works:**
- `WorkoutPlanEditor` can select/deselect partners and order the roster, but
  **only in Edit mode** (`isEditing`), and the coach plan opens in *view* mode
  (`WeightsStartView` / `SelectWorkoutView` construct it with
  `startInEditMode` defaulted to `false`).
- `EditablePlan.partnerIDs: [UUID]` exists and `apply(to:)` writes
  `session.activePartnerIDs`.
- **At runtime**, `SessionRenderModel.build(...)`
  (`CadenceCore/Sources/CadenceFeatures/SessionRenderModel.swift:216-320`)
  already resolves *per-performer* pending sets: for each performer it reads
  `WorkoutRepository.firstWorkingSetWeight(for:performedBy:excluding:)` and
  `WorkoutRepository.repLadderHistory(for:performedBy:excluding:)`, falls back to
  a `generalRepLadderHistory`, and finally to the planned target.

**Missing (this phase):**
- The *plan editor* shows only the owner's ladder — a partner's plan is invisible
  until the workout has started.
- `EditablePlan`/`EditableExercise` have no per-performer prescription, so
  nothing can be reviewed or edited before Start.
- `WorkoutSession` has nowhere to persist a per-performer prescription, so an
  edited partner plan would be lost on launch.

## 2. Design

```
Workout Plan                                    [Edit]
┌──────────────────────────────────────────────┐
│  ▶  Start Workout                            │
└──────────────────────────────────────────────┘
┌─ Training partners ─────────────────── ＋ ───┐
│ ☑ Alex          ☐ Sam                        │   ← now available in VIEW mode
│ Performer order:  Me › Alex                  │
└──────────────────────────────────────────────┘
┌─ Bench Press ────────────────────────────────┐
│ Me     80 kg×8, 85 kg×6, 90 kg×5             │
│ Alex   60 kg×8, 62.5 kg×6, 65 kg×5           │  ← from Alex's own history
└──────────────────────────────────────────────┘
┌─ Overhead Press ─────────────────────────────┐
│ Me     45 kg×10, 47.5 kg×8, 50 kg×6          │
│ Alex   — ×10, — ×8, — ×6                     │  ← Alex has no history here:
└──────────────────────────────────────────────┘     owner's reps, no weight
```

Rules (decisions **D12**, **D13**):
- The partner's exercise list and set count **always equal the owner's**. The
  coach never adds or removes exercises for a partner — they are working in on
  the owner's sets.
- Only **reps and weight** are personalized, and only from that partner's own
  logged history. A partner never inherits the owner's weight.
- Adding a partner re-resolves their plan immediately; removing them drops it.
- Swapping an exercise re-resolves every performer's plan for that exercise.

## 3. Model changes

### 3a. `CadenceCore/Sources/CadenceCore/Models.swift`

Additive value type next to `PlannedExercisePrescription`:

```swift
/// One performer's prescription for a session. `performerID` is a `Person.id`
/// UUID string; nil ⇒ the device owner. Additive (decision D11): the owner's
/// plan continues to live in `plannedPrescriptions`, and any performer without an
/// entry here falls back to it, so every legacy session and older JSON export
/// keeps working untouched.
public struct PlannedPerformerPrescription: Codable, Equatable, Sendable {
    public var performerID: String?
    public var exercises: [PlannedExercisePrescription]
    public init(performerID: String?, exercises: [PlannedExercisePrescription])
}
```

`WorkoutSession` gains **one** stored property + its computed accessor, mirroring
`plannedPrescriptionsData` exactly:

```swift
/// JSON-encoded per-performer prescriptions. Additive and defaulted for CloudKit
/// and legacy sessions (CloudKit rule: defaulted, non-unique, no new relationship).
private var plannedPerformerPrescriptionsData: String = ""

public var plannedPerformerPrescriptions: [PlannedPerformerPrescription] {
    get { … decode, [] on failure … }
    set { … encode, "" on failure … }
}

/// The prescription for one performer, falling back to the owner's plan.
public func plannedPrescriptions(forPerformerID id: UUID?) -> [PlannedExercisePrescription] {
    if let match = plannedPerformerPrescriptions.first(where: {
        $0.performerID == id?.uuidString
    }) { return match.exercises }
    return plannedPrescriptions
}
```

CloudKit compliance check: defaulted `String`, no `@Attribute(.unique)`, no new
relationship — compliant.

### 3b. `CadenceCore/Sources/CadenceCore/DataExport.swift`
Add `public var plannedPerformerPrescriptions: [PlannedPerformerPrescription]?`
to the session DTO (optional, defaulted `nil` in `init`), write it on export and
read it on import, next to the existing `plannedPrescriptions` handling
(lines 103-122). Older exports decode with `nil` and behave exactly as today.

### 3c. `CadenceCore/Sources/CadenceFeatures/EditablePlan.swift`

```swift
/// One performer's set plan inside an editable exercise. `performerID == nil`
/// is the owner ("Me"), always first.
public struct EditablePerformerPlan: Identifiable, Hashable {
    public let id = UUID()
    public var performerID: UUID?
    public var name: String            // "Me" or the partner's name
    public var sets: [EditableSet]
    public var isMe: Bool { performerID == nil }
}
```

`EditableExercise` gains:
```swift
/// Per-performer plans. Empty ⇒ solo; `sets` remains the owner's plan and the
/// source of truth for set COUNT (decision D12).
public var performerPlans: [EditablePerformerPlan] = []
```
Add a defaulted parameter to `init` so every existing construction compiles.

`EditablePlan.apply(to:)` additionally writes:
```swift
session.plannedPerformerPrescriptions = performerPrescriptions()
```
where `performerPrescriptions()` maps each exercise's `performerPlans` into
`PlannedPerformerPrescription`s grouped by performer, skipping the owner (whose
plan is already `plannedPrescriptions`) — or including the owner for symmetry;
either is fine as long as `plannedPrescriptions(forPerformerID:)` resolves both.
**Include the owner** so the two paths stay identical and there is one code path
to test.

`EditablePlan.from(session:)` reads them back so "start from a previous workout"
preserves partner plans.

## 4. New pure resolver — `CadenceCore/Sources/CadenceFeatures/PartnerPlanResolver.swift`

The app cannot pass `@Model` rows into a pure function safely, so the resolver
takes a plain history value the view assembles from `WorkoutRepository`.

```swift
import Foundation
import CadenceCore

/// Fills a training partner's plan from *their own* logged history, for the
/// owner's exercises only (field test 2026-08-18 #4). Mirrors the resolution
/// SessionRenderModel already performs at set-logging time, moved forward to the
/// plan editor so the partner's plan is reviewable before Start.
public enum PartnerPlanResolver {

    /// One performer's history for ONE exercise, gathered by the caller from
    /// WorkoutRepository. All weights canonical kg.
    public struct ExerciseHistory: Equatable, Sendable {
        /// Most recent prior session's working sets, in logged order.
        public let lastSets: [(weightKg: Double, reps: Int)]
        /// Working-set rep ladders for this exercise, oldest first.
        public let repLadders: [[Int]]
        /// The performer's first working weight for this exercise, if any.
        public let firstWorkingWeightKg: Double?
        /// The performer's general rep pattern across ALL exercises, oldest
        /// first — used when they have never trained THIS movement.
        public let generalRepLadders: [[Int]]
        public static let empty: ExerciseHistory
    }

    /// Resolve one partner's sets for one exercise.
    ///
    /// Order (decision D13):
    ///  1. history for THIS exercise → their ladder (index-wise, extended by
    ///     repeating the last rep count) + their first working weight;
    ///  2. else their general rep pattern → those reps, weight nil;
    ///  3. else the owner's planned reps, weight nil.
    /// The result ALWAYS has `ownerSets.count` elements (decision D12).
    public static func sets(forOwnerSets ownerSets: [EditableSet],
                            history: ExerciseHistory) -> [EditableSet]

    /// Rebuild every exercise's `performerPlans` for the given roster.
    /// `history(exerciseName, performerID)` is supplied by the caller.
    public static func fill(plan: EditablePlan,
                            roster: [(performerID: UUID?, name: String)],
                            history: (String, UUID?) -> ExerciseHistory) -> EditablePlan

    /// The owner's own plan as a performer entry, so "Me" is always index 0.
    public static func ownerPlan(name: String, ownerSets: [EditableSet]) -> EditablePerformerPlan
}
```

Constraints on `sets(forOwnerSets:history:)`:
- Never returns more or fewer sets than `ownerSets.count`.
- `lastSets` shorter than `ownerSets` → repeat the last logged rep/weight.
- `lastSets` longer → truncate.
- Reps of 0 or negative are treated as absent (fall through to the next rule).
- Weight resolution: `lastSets[i].weightKg` when > 0, else
  `firstWorkingWeightKg`, else `nil`. Never the owner's weight.

## 5. View changes

### `Home/WorkoutPlanPartnerSection.swift` (created in Phase 2)
- Show the **partner picker in view mode too**, not only under `isEditing`.
  Collapse it to a compact chip row plus a `＋` button that reveals the full
  picker, so the read-only plan does not become a wall of controls:
  ```
  Training partners     Solo   ＋
  Training partners     Alex ✕   ＋
  ```
- Adding/removing a partner calls back into the editor to re-resolve
  (`onRosterChanged`).
- Keep every existing identifier: `editor.partner.<name>`,
  `editor.newPartnerName`, `editor.addPartner`,
  `editor.partnerOrder.up.<name>`, `editor.partnerOrder.down.<name>`.
  New: `editor.partners` (card), `editor.partnerChip.<name>`,
  `editor.removePartner.<name>`, `editor.showPartnerPicker`.

### `Home/WorkoutPlanExerciseSection.swift` (created in Phase 2)
- View mode: render one line **per performer**, Me first, using the same
  abbreviated format as Phase 4's summary
  (`WorkoutSummaryPresenter`-style; extract the shared formatter into
  `CadenceFeatures` rather than duplicating it — put
  `PlannedSetsFormatter.line(sets:unit:isBodyweight:)` in
  `WorkoutSummaryPresenter.swift` or a new `PlanFormatting.swift` and call it
  from both).
- Edit mode: a performer segmented picker above the set rows so the user can edit
  any performer's reps/weight; default selection "Me".
- Ids: `editor.compactExercise.<name>` (unchanged, owner line),
  `editor.exercisePerformer.<name>.<performer>`,
  `editor.performerPicker.<name>`.

### `Home/WorkoutPlanEditor.swift`
- On `.onAppear` and whenever `plan.partnerIDs` changes, call
  `resolvePartnerPlans()`:
  ```swift
  private func resolvePartnerPlans() {
      let roster = editorRoster.map { (performerID: $0.isMe ? nil : $0.id, name: $0.isMe ? "Me" : $0.name) }
      plan = PartnerPlanResolver.fill(plan: plan, roster: roster) { name, performerID in
          history(forExerciseNamed: name, performerID: performerID)
      }
  }
  ```
- `history(forExerciseNamed:performerID:)` looks the `Exercise` up via
  `WorkoutRepository.findOrCreateExercise(named:in:)` **without creating** —
  prefer a read-only lookup; if none exists, return `.empty`. Then fills
  `ExerciseHistory` from
  `WorkoutRepository.lastTimeSets(for:performedBy:excluding: nil)`,
  `.repLadderHistory(for:performedBy:excluding: nil)`,
  `.firstWorkingSetWeight(for:performedBy:excluding: nil)`, and a general ladder
  built from the person's recent sessions.
- Re-resolve after `applyPickedExercise` (add **and** swap).
- Guard performance: the resolver runs on roster/exercise changes only, never per
  keystroke.

### `SessionRenderModel`
When `session.plannedPerformerPrescriptions` has an entry for a performer, use
`session.plannedPrescriptions(forPerformerID:)` for that performer's
`plannedSets` instead of the owner's `plannedSets` (line ~275). Everything else
(history-driven rep adjustment, `firstWorkingWeightKg`) stays as-is — the stored
plan becomes a better *starting* target, not a replacement for their history.

## 6. Tests

### New — `CadenceCore/Tests/CadenceFeaturesTests/PartnerPlanResolverTests.swift`
```
testPartnerWithExactExerciseHistoryGetsTheirOwnLadderAndWeight
testPartnerWeightNeverInheritsTheOwnersWeight
testPartnerWithNoExerciseHistoryUsesTheirGeneralRepPattern
testPartnerWithNoHistoryAtAllUsesOwnerRepsWithNoWeight
testResolvedSetCountAlwaysMatchesTheOwnersSetCount
testShorterPartnerHistoryRepeatsTheLastLoggedSet
testLongerPartnerHistoryIsTruncatedToTheOwnersSetCount
testZeroOrNegativeRepsAreTreatedAsMissing
testOwnerIsAlwaysTheFirstPerformerPlan
testFillIsIdempotent                      // running it twice changes nothing
testRemovingAPartnerDropsTheirPerformerPlan
testAddingAPartnerLeavesTheOwnerPlanUntouched
testBodyweightExerciseResolvesWithNilWeightForEveryPerformer
```

### `CadenceCore/Tests/CadenceFeaturesTests/EditablePlanTests.swift` (extend)
```
testApplyWritesPerformerPrescriptionsForEveryRosterMember
testApplyStillWritesTheOwnerPlanToPlannedPrescriptions   // back-compat
testFromSessionRoundTripsPerformerPlans
testLegacySessionWithoutPerformerDataResolvesToTheOwnerPlan
```

### `CadenceCore/Tests/CadenceCoreTests/WorkoutRepositoryTests.swift` (extend)
```
testPlannedPrescriptionsForPerformerFallsBackToTheOwnerPlan
testPlannedPerformerPrescriptionsEncodeAndDecode
testEmptyPerformerDataDecodesToEmptyArray
```

### `CadenceCore/Tests/CadenceCoreTests/DataExportTests.swift` (extend)
```
testExportRoundTripsPerformerPrescriptions
testImportOfALegacyExportWithoutPerformerPrescriptionsSucceeds
```

### `CadenceCore/Tests/CadenceFeaturesTests/SessionRenderModelTests.swift` (extend)
```
testPendingSetsUseThePerformersStoredPrescriptionWhenPresent
testPendingSetsFallBackToTheOwnerPrescriptionWhenAbsent
testPartnerHistoryStillOverridesRepsWithinTheStoredPlan
```

### UI smoke — inside the single existing test
After opening the plan editor:
```swift
// Field test 2026-08-18 #4: partners are addable from the plan, not only in Edit.
XCTAssertTrue(app.descendants(matching: .any)["editor.partners"].waitForExistence(timeout: 5),
              "Workout Plan does not expose Training partners outside Edit mode")
```

## 7. Acceptance criteria

- [ ] Training partners can be added and removed from the coach's Workout Plan
      **without** entering Edit mode.
- [ ] Adding a partner immediately fills their plan for **every** exercise in the
      owner's plan, with the same set count.
- [ ] A partner with history for an exercise gets **their** reps and **their**
      weight.
- [ ] A partner with history elsewhere but not for that exercise gets their
      general rep pattern and no weight.
- [ ] A partner with no history gets the owner's reps and no weight — never the
      owner's weight.
- [ ] The coach never adds or removes an exercise for a partner.
- [ ] Each exercise in the plan shows one line per performer, `Me` first.
- [ ] Starting the workout carries every performer's plan into the session
      (`plannedPerformerPrescriptions`), and the logger's pending sets honour it.
- [ ] A session saved before this phase, and a JSON export made before this
      phase, both import and render unchanged.
- [ ] `WorkoutPlanEditor.swift`, `WorkoutPlanPartnerSection.swift`,
      `WorkoutPlanExerciseSection.swift` each ≤ 400 LOC.
- [ ] `make ci` green; `make smoke` green; `make watch-smoke` green (the watch
      reads sessions and must be unaffected by the new field).

## 8. Migration safety

- The new SwiftData property is a defaulted `String` — no destructive migration,
  no CloudKit schema break beyond an additive field. **A CloudKit schema deploy
  to Production is required before a TestFlight/production build syncs it**
  (same rule as any additive field — note it in `current_status.md`).
- `plannedPrescriptions` is untouched, so every existing reader (watch sync,
  export, `SessionRenderModel`'s fallback) keeps working with no knowledge of the
  new field.

## 9. Commit

```
feat: coach fills each training partner's plan from their own history

Field test 2026-08-18 #4. Partners can be added from the Workout Plan itself;
each partner's reps and weights are resolved from their own logged history for
the owner's exercises only, so they can work in on the same sets. Stored
additively as plannedPerformerPrescriptions and honoured by the logger.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

Update `current_status.md` — including the CloudKit production-deploy note and
the final batch summary — commit, **do not push**, report, stop.
