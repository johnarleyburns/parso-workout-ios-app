# Phase 3 — Coach plan shows real weights (`BW×12` bug)

Field-test issue #2: *"coach's suggested workout appears to have incorrect
weights when I see the Workout Plan it's always BWx12 etc even for non-bodyweight
exercises like Standing Dumbbell Upright Row, investigate and fix."*

**The investigation is already done.** Do not re-derive it — implement the fix.

## 1. Root cause (established, verified by reading the code)

Chain: `CoachPlanOptimizer` → `CoachSession.RecommendedExercise.loadKg` →
`EditablePlan.from(coach:)` → `EditableSet.targetWeight` → `CompactExerciseRow`.

**Cause A — the load lookup only sees the last 7 days.**
`CoachPlanOptimizer.suggestedLoadKg(for:trainingFacts:)`
(`CadenceCore/Sources/CadenceCore/CoachPlanOptimizer.swift:1123`) resolves load
from `TrainingFacts.liftSnapshots`. `TrainingFacts.make`
(`CadenceCore/Sources/CadenceCore/TrainingFacts.swift:257-275`) builds
`liftSnapshots` from `weekSets` — **the trailing week only**. Any lift the user
last trained 8+ days ago resolves to `nil` and renders as `BW`.

**Cause B — anti-repeat rotation strips the load unconditionally.**
`CoachPlanOptimizer.varietyAlternative(...)` (~line 723) constructs its
replacement with a hard-coded `loadKg: nil`, and `rotatedForVariety` (~line 661)
is never given `trainingFacts`, so it cannot resolve one. Every exercise swapped
in for cross-day variety — precisely the isolation movements like *Standing
Dumbbell Upright Row* — loses its weight.

**Cause C — the renderer conflates "no load" with "bodyweight".**
`Cadence/Cadence/Features/Home/CompactExerciseRow.swift:26-29`:
```swift
let weight = set.targetWeight.map { Format.weightValue($0, unit: unit) } ?? "BW"
```
A loaded movement with unknown history is labelled `BW`, which is factually
wrong (decision **D4**).

## 2. Fix

### 2a. New public bodyweight predicate — `CadenceCore`

`PrescriptionMath.isBodyweightMovement(named:)` exists at
`CadenceCore/Sources/CadenceCore/RecommendationRule.swift:304` but `enum
PrescriptionMath` is internal. Add a public façade in a **new** file
`CadenceCore/Sources/CadenceCore/ExerciseLoading.swift`:

```swift
import Foundation

/// Public façade over the load-classification rules the coach and the UI both
/// need. Kept separate from `PrescriptionMath` (internal, rule-engine detail) so
/// the app can ask "should this render as BW?" without importing rule internals.
public enum ExerciseLoading {
    /// True when the movement is performed against bodyweight — catalog
    /// equipment wins, keyword fallback covers user-created movements.
    public static func isBodyweight(named name: String) -> Bool {
        PrescriptionMath.isBodyweightMovement(named: name)
    }

    /// True when the movement is programmed as a timed hold rather than reps.
    public static func isTimeHold(named name: String) -> Bool {
        PrescriptionMath.isTimeHold(named: name)
    }
}
```

### 2b. All-history load resolution — `CoachSession`

Add next to the existing `recentTopReps(forExerciseNamed:facts:)`
(`CadenceCore/Sources/CadenceCore/CoachSession.swift:601`), using the same
canonical-name matching:

```swift
/// The user's most recent logged top set for a movement across ALL history
/// (matched by canonical name), newest first. `liftSnapshots` only covers the
/// trailing week, so this is what keeps a plan's weights real for anything
/// trained more than seven days ago (field test 2026-08-18 #2).
static func recentTopSet(forExerciseNamed name: String,
                         facts: CoachFacts) -> (weightKg: Double, reps: Int, bestE1RM: Double)? {
    let target = MuscleCatalog.canonicalName(name)
    var best: (weightKg: Double, reps: Int, bestE1RM: Double, at: Date)?
    for event in facts.events {
        guard case .strength(let details) = event.kind, let d = details else { continue }
        for ex in d.exercises
        where MuscleCatalog.canonicalName(ex.exerciseName) == target && ex.topSetWeightKg > 0 {
            if best == nil || ex.lastWorkingSetAt > best!.at {
                best = (ex.topSetWeightKg, ex.topSetReps, ex.bestE1RM, ex.lastWorkingSetAt)
            }
        }
    }
    return best.map { ($0.weightKg, $0.reps, $0.bestE1RM) }
}
```

`StrengthEventDetails.PerExercise` already carries `topSetWeightKg`,
`topSetReps`, `bestE1RM` and `lastWorkingSetAt`
(`CadenceCore/Sources/CadenceCore/TrainingEvent.swift:16-28`) — no model change.

### 2c. Extend `suggestedLoadKg` — `CoachPlanOptimizer`

```swift
private static func suggestedLoadKg(for exercise: CoachSession.RecommendedExercise,
                                    trainingFacts: TrainingFacts?,
                                    coachFacts: CoachFacts?) -> Double? {
    // A bodyweight movement genuinely has no external load — never invent one.
    guard !ExerciseLoading.isBodyweight(named: exercise.name) else { return nil }

    let reps = exercise.repLadder?.first ?? exercise.repsLow

    // 1. Trailing-week snapshot (unchanged behaviour, keeps existing tests green).
    if let facts = trainingFacts,
       let snapshot = facts.liftSnapshots.first(where: {
           $0.key.caseInsensitiveCompare(exercise.name) == .orderedSame
       })?.value,
       snapshot.bestE1RM > 0 {
        let r = reps ?? snapshot.topSetReps
        if r > 0, let load = load(fromE1RM: snapshot.bestE1RM, reps: r) { return load }
    }

    // 2. All-history fallback (field test 2026-08-18 #2).
    if let coachFacts,
       let top = CoachSession.recentTopSet(forExerciseNamed: exercise.name, facts: coachFacts),
       top.bestE1RM > 0 {
        let r = reps ?? top.reps
        if r > 0, let load = load(fromE1RM: top.bestE1RM, reps: r) { return load }
    }
    return nil
}

/// Inverse-e1RM at the planned rep target, rounded to the nearest half unit.
private static func load(fromE1RM e1rm: Double, reps: Int) -> Double? {
    let suggested = WeightSuggestion.inverseE1RM(e1rm: e1rm, reps: reps, formula: .epley)
    return suggested > 0 ? (suggested * 2).rounded() / 2 : nil
}
```

Update the single call site in `copy(...)` (line ~1115) to pass `coachFacts`.

### 2d. Give rotation its load back — `CoachPlanOptimizer`

- `rotatedForVariety(_:usedThisWeek:trainingFacts:coachFacts:slot:policy:)`
  already receives `trainingFacts` — it just doesn't forward it.
- Add `trainingFacts:` to `varietyAlternative(for:avoiding:coachFacts:slot:policy:)`
  and replace the hard-coded `loadKg: nil` with
  `suggestedLoadKg(for: candidate, trainingFacts: trainingFacts, coachFacts: coachFacts)`
  where `candidate` is built with the resolved `repLadder`/`repsLow` **before**
  the load lookup (order matters — `suggestedLoadKg` reads `repLadder.first`).

### 2e. Renderer honesty — `CompactExerciseRow`

```swift
private func compactSetLine(_ set: EditableSet) -> String {
    if let w = set.targetWeight { return "\(Format.weightValue(w, unit: unit))×\(set.targetReps)" }
    return isBodyweight ? "BW×\(set.targetReps)" : "—×\(set.targetReps)"
}
```
with `private var isBodyweight: Bool { ExerciseLoading.isBodyweight(named: exercise.name) }`.

Apply the same rule to `WorkoutPlanExerciseSection.setRow` (Phase 2's extraction)
and to `HomeCoachRecommendationCard.previewDetails`, which today silently omits
the weight when `loadKg` is nil — after this phase it shows `BW` for bodyweight
movements and nothing (as today) for genuinely unknown loads.

## 3. Tests

### `CadenceCore/Tests/CadenceCoreTests/CoachPlanOptimizerTests.swift` (extend)
```
testPlannedLoadResolvesFromHistoryOlderThanOneWeek
    // session 21 days ago: Standing Dumbbell Upright Row @ 20 kg × 12
    // → optimized plan's exercise has loadKg ≈ inverseE1RM(...) > 0
testVarietyRotationKeepsAResolvedLoad
    // usedThisWeek forces a swap; the alternative has a non-nil loadKg when the
    // user has history for it
testBodyweightMovementKeepsNilLoad
    // "Push-Up" with history stays loadKg == nil
testUntrainedLoadedMovementKeepsNilLoad
    // no history → nil (we do not invent a weight)
testTrailingWeekSnapshotStillWins
    // an exercise present in liftSnapshots resolves from the snapshot, unchanged
```

### New — `CadenceCore/Tests/CadenceCoreTests/ExerciseLoadingTests.swift`
```
testCatalogBodyweightMovementsAreDetected      // "Push-Up", "Pull-Up", "Dip"
testLoadedMovementsAreNotBodyweight            // "Standing Dumbbell Upright Row",
                                               // "Bench Press", "Barbell Curl"
testTimeHoldsAreDetected                       // "Plank", "Wall Sit"
```
The `Standing Dumbbell Upright Row` case is the field-test regression — assert it
explicitly by name.

### New — `CadenceCore/Tests/CadenceCoreTests/CoachSessionRecentTopSetTests.swift`
```
testRecentTopSetPrefersTheNewestEvent
testRecentTopSetMatchesByCanonicalName        // alias/casing differences resolve
testRecentTopSetIgnoresZeroWeightSets
testRecentTopSetIsNilWithNoHistory
```

### `CadenceCore/Tests/CadenceFeaturesTests/EditablePlanTests.swift` (extend)
```
testCoachPlanCarriesResolvedWeightsIntoEditableSets
testCoachPlanBodyweightExerciseHasNilTargetWeight
```

### `CadenceCore/Tests/CadenceCoreTests/RecommendationPrescriptionTests.swift`
Re-run; must stay green (the trailing-week path is unchanged).

### UI smoke
No change required. (The seeded UI-test store has no multi-week history, so this
is not observable there — it is fully covered headlessly.)

## 4. Acceptance criteria

- [ ] A movement last trained >7 days ago appears in the coach's Workout Plan
      with a real weight, not `BW`.
- [ ] An exercise substituted by cross-day variety rotation carries a weight.
- [ ] A genuine bodyweight movement still shows `BW`.
- [ ] A loaded movement the user has never logged shows `—`, never `BW`.
- [ ] `ExerciseLoading` is the only public bodyweight predicate; the app does not
      re-implement keyword matching.
- [ ] No existing coach test regressed (`CoachPlanOptimizerTests`,
      `CoachExerciseVarietyTests`, `CoachBodyweightPrescriptionTests`,
      `RecommendationPrescriptionTests`, `WeightSuggestionTests`,
      `SameDayLoadRegressionTests`).
- [ ] `make ci` green. `make smoke` green.

## 5. Commit

```
fix: coach plans carry real loads instead of BW

Field test 2026-08-18 #2. liftSnapshots only covers the trailing week and
variety rotation dropped loadKg outright, so any lift trained 8+ days ago — or
swapped in for variety — rendered as BW×12. Load now falls back to all-history
top sets, rotation resolves its own load, and the editor only prints BW for
movements that are actually bodyweight.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

Update `current_status.md`, commit, **do not push**, report, stop.
