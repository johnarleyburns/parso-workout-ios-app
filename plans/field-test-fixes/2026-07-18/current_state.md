# Current State — field-test fixes 2026-07-18

Updated per phase. Test count baseline: 1184 before any phase.

## Phase A — Single isResumable source of truth + never-block gate ✅ SHIPPED

### Test proof (fail-first)
- `SessionEligibilityPolicyTests.testActiveWorkoutDoesNotBlockEligibleCandidate`: FAILED on current code (deferred with `activeWorkout` reason). PASSED after fix.
- `ActiveSessionRecoveryTests.testIsResumableMatchesCoachingInProgress`: FAILED to compile (`isResumable` didn't exist). PASSED after fix.

### Changes
1. **CadenceCore/Models.swift**: Added `WorkoutSession.isResumable` computed property
2. **CadenceFeatures/ActiveSessionRecovery.swift**: Refactored `candidate(in:)` to use `isResumable`
3. **CadenceCore/SessionEligibilityPolicy.swift**: Removed active-workout defer (lines 37-41)
4. **CadenceCore/CoachDecision.swift**: Added `activeWorkout` warning in `CoachDecisionEngine.run`
5. **HomeView.swift**: Resume card now falls back to `ActiveSessionRecovery.candidate(in: sessions)` when `active.strengthSession` is nil; on-tap adopts + presents

### Test counts
- CadenceCoreTests: 892 → 893 (+1)
- CadenceFeaturesTests: 295 → 296 (+1)
- Total: 1184 → 1186 (+2)

## Phase B — Coach hero copy from logged work (CoachHeroPresenter) ✅ SHIPPED

### Test proof (fail-first)
- `CoachHeroPresenterTests` (5 new tests): FAILED to compile before `CoachHeroPresenter` existed. All 5 PASS after implementation.
  - `testDeferredCandidatesDoNotProduceLoggedExercises` — proves the "Air Squat and Air Squat" defect
  - `testCompletedTodayStrengthShowsExerciseNames` — logs Snatch + Lat Pulldown from completed session
  - `testNoDuplicateExerciseNames` — dedup verification
  - `testCompletedTodayStrengthAllowsCardioCard` — cardio primary when strength already done
  - `testCompleteStateReturnsCorrectTitle`

### Changes
1. **CadenceFeatures/CoachHeroPresenter.swift**: New pure presenter — computes hero title/subtitle from logged work (not deferred candidates)
2. **CadenceFeatures/TodayLogHelper.swift**: Extracts today's completed strength sessions from `[WorkoutSession]`
3. **CoachDecisionCardView.swift**: Replaced `heroTitle`/`heroSubtitle`/`recentlyTrainedExercises` with `CoachHeroPresenter.present()`; uses `hasTodayStrengthCompleted`/`todayLoggedExerciseNames` params instead of checking deferred candidates
4. **HomeView.swift**: Computes `hasTodayStrengthCompleted` + `todayLoggedExerciseNames` via `TodayLogHelper`, passed to `CoachDecisionCardView`

### Test counts
- CadenceCoreTests: 893 → 895 (+2)
- CadenceFeaturesTests: 296 → 301 (+5)
- Total: 1189 → 1193 (+4 — B + C combined)

## Phase C — Decision fallback rescues still-due cardio ✅ SHIPPED

### Test proof
- `testCardioRescueBeforeRestFallback`: primary must not be rest.fallback when cardio unmet
- `testDeferredAllButCardioNeededStillGetsTrainable`: verifies cardio rescue in fallback

### Changes
1. **CoachDecision.swift**: Extended empty-eligible rescue to check cardio need before rest.fallback

### Test counts
- CadenceCoreTests: 895 (was 893)
- CadenceFeaturesTests: 301 (unchanged)
- Total: 1193 (was 1191, +2)

## Phase D — True today-list TodayActivityPresenter for "What you did" ✅ SHIPPED

### Test proof
- `TodayActivityPresenterTests` (10 new tests): all pass — includesOnlyToday, inProgressExcluded, deletedExcluded, multipleSameDayAllListed, mixedSortedNewestFirst, midnightBoundary, unitFormatting, emptyDay, multipleStrengthTodayAllVisible, resumableExcluded

### Changes
1. **CadenceFeatures/TodayActivityPresenter.swift**: New presenter returns all completed (non-resumable) workouts from today
2. **HomeView.swift**: Replaced `whatYouDidFacts` (coachDecision.observedFacts filter) with `TodayActivityPresenter.entries()`. Empty copy: "Nothing yet today." Reduced to 1102 LOC (was 1113).

### Test counts
- CadenceCoreTests: 895 (unchanged)
- CadenceFeaturesTests: 301 → 311 (+10)
- Total: 1193 → 1203 (+10)

## Phase E — Swap via sheet(item:) + Remove on planned-only cards ✅ SHIPPED

### Test proof
- `ExerciseSwapTests` (4 new tests): swapTarget survives dismissal, changeExercise moves sets + dedups, removePlannedExercise removes exactly that card, removeExercise deletes sets + name on completed workout

### Changes
1. **CadenceFeatures/ExerciseSwap.swift**: New `SwapTarget` enum for `.sheet(item:)` — payload rides the item
2. **ExercisePickerView.swift**: Reordered detail-path to `onPick(picked); dismiss()` (match row path)
3. **SessionView.swift**: Replaced two derived-`isPresented` sheets with one `.sheet(item: $swapTarget)`; removed `changingExerciseFor` and `swappingPlannedName` state vars; `plannedCard` now uses ellipsis Menu (Swap + Remove); confirmationDialog uses `WorkoutRepository.removeExercise`
4. **WorkoutRepository.swift**: Added `removeExercise` and `removePlannedExercise` methods
5. SessionView stays at 1101 LOC (ratchet ≤1102)

### Test counts
- CadenceCoreTests: 895 → 897 (+2)
- CadenceFeaturesTests: 315 (unchanged — tests live in CadenceCoreTests)
- Total: 1207 → 1216 (+9 — F + G combined, 2 CoachFacts/Snapshot + 9 WeightSuggestion)

## Phase F — "Your Plan" uses cached coach facts ✅ SHIPPED

### Test proof
- `CoachSnapshotBuilderTests.testCoachFactsExposedAndConsistent`: coachFacts exposed + consistent
- `CoachFactsTests.testWithStepSummaryPopulatesStepsPreservingOtherFields`: stepSummary overlay works

### Changes
1. **CoachSnapshotBuilder.swift**: Added `coachFacts: CoachFacts` to `CoachSnapshot`, plumbed through builder
2. **CoachFacts.swift**: Added `withStepSummary(from:)` method
3. **HomeCoachSnapshot.swift**: Mirrored `coachFacts`
4. **HomeView.swift**: `.yourPlan` and `strengthAnyway` use `coachSnapshot.coachFacts.withStepSummary(from:)`; removed `buildTrainingEvents()`
5. HomeView: 1089 LOC (was 1104)

## Phase G — Per-rep-count weight autofill + inverse-e1RM fallback ✅ SHIPPED

### Test proof
- `WeightSuggestionTests` (9 tests): exactRepMatchWins, mostRecentExactMatchPreferred, e1RMScalesFromBestRecentSet, e1RMUsesChosenFormula, warmupsExcluded, partnerHistoryFullySeparated, roundTripSelfConsistency, noHistoryReturnsNil, everyEmittedCitationIdResolves

### Changes
1. **CadenceCore/WeightSuggestion.swift**: `suggest(targetReps:history:formula:)` — exact-rep match wins, falls back to inverse Epley/Brzycki from best recent set
2. **WorkoutRepository.swift**: `performerSetHistory(for:performedBy:excluding:)` — raw-weight, non-warmup, per-performer, newest first
3. **CadenceFeatures/InlineEditorDefaults.swift**: Cascade integration — current-session-exact → WeightSuggestion → prescribed load → nil
4. Citation hard rule: `everyEmittedCitationIdResolves` proves `oneRMEstimation` citation ID resolves

### Test counts
- CadenceCoreTests: 897 → 906 (+9)
- CadenceFeaturesTests: 315 (unchanged)
- Total: 1216 (was 1207 from Phase E, +9 from F/G combined)

## Summary — All phases complete

| Phase | SHA | Description |
|-------|-----|-------------|
| A | `19661f6` | isResumable + never-block gate |
| B | `7c36fbf` | CoachHeroPresenter from logged work |
| C | `917c0e9` | Cardio rescue before rest fallback |
| D | `17920b3` | TodayActivityPresenter |
| E | `635aa3a` | Swap via sheet(item:) + Remove |
| F | `f347f8b` | Your Plan uses cached coachFacts |
| G | `33e265b` | Weight autofill + inverse-e1RM |

Test counts: 1184 → 1216 (+32 across 7 phases)
All launch-blocker items covered: 3→E, 4→G, 5→D, Step 6→F
