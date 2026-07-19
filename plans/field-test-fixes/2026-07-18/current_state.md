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
- CadenceCoreTests: 895 (unchanged)
- CadenceFeaturesTests: 311 → 315 (+4)
- Total: 1203 → 1207 (+4)
