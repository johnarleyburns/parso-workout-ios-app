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
- CadenceCoreTests: 893 (unchanged)
- CadenceFeaturesTests: 296 → 301 (+5)
- Total: 1189 → 1191 (+2 including TodayLogHelper)
