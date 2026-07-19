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
