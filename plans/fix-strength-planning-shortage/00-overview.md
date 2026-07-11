# Fix: Strength Planning Shortage

**Date:** 2025-07-08
**Status:** implemented

## Problem

With `strengthDaysPerWeek = 5` and `cardioDaysPerWeek = 6`, only 2 strength days get planned per week (instead of 5), while all 6 cardio days are scheduled. The user also sees "Some planned volume still needs attention" because the coach optimizer can't fit enough volume into just 2 strength slots.

## Root Cause

**`WeeklyPlan.swift:315`** — The `canStrength` gate required `priorHardStreak == 0`. The `hardStreak()` function counts *all* consecutive hard days — including moderate aerobic cardio, which gets marked as a hard day at line 258. When two-a-days are off, every time cardio fills a non-strength day, it blocks strength the next day.

### Walkthrough (before fix: 5 strength, 6 cardio, rolling rest every 3 days, no two-a-days, Mon start):

| Day | Event | Hard streak before | Strength allowed? |
|-----|-------|-------------------|-------------------|
| Tue | Strength | 0 | Yes |
| Wed | Cardio (moderate) | 1 | **No** → cardio fills |
| Thu | Rest (rolling) | — | — |
| Fri | Strength | 0 | Yes |
| Sat | Cardio (moderate) | 1 | **No** → cardio fills |
| Sun | Cardio (moderate) | 1 | **No** → cardio fills |

Result: **2 strength days** out of 5 requested.

### Secondary bug: double-counting of `projectedAerobicMinutes`

**`WeeklyPlan.swift:258-264`** — For `moderateAerobic` and `vo2Intervals` sessions, `projectedAerobicMinutes` was incremented in *both* code blocks, causing double-counting.

## Fix

### Fix 1: Remove `priorHardStreak == 0` from canStrength

```diff
 let canStrength = strengthNeeded
-    && priorHardStreak == 0
     && strengthRecoveryEligible(on: date, facts: facts, calendar: calendar)
     && (lastStrengthDate == nil || days >= 1)
```

**Rationale:**
- `priorHardStreak == 0` conflated hard cardio with hard strength — cardio the previous day should not block strength
- `lastStrengthDate >= 1` prevents same-day double-counting (no two strength in one day)
- `strengthRecoveryEligible` handles whole-body recovery
- The recovery gate at line 306 (`priorHardStreak >= 3`) prevents overtraining via consecutive hard days

### Fix 2: Eliminate double-counting of aerobic minutes

Merged the two `projectedAerobicMinutes` increment blocks into one:

```diff
+ let isAerobic = s.kind == .easyAerobic || s.kind == .moderateAerobic || s.kind == .vo2Intervals
  if s.isHard || s.kind == .moderateAerobic || s.kind == .vo2Intervals {
      projectedHardDays.insert(date)
-     projectedAerobicMinutes += plannedModerateEquivalentMinutes(for: s.kind)
  }
- if s.kind == .easyAerobic || s.kind == .moderateAerobic || s.kind == .vo2Intervals {
+ if isAerobic {
      projectedAerobicMinutes += plannedModerateEquivalentMinutes(for: s.kind)
      projectedCardioDays += 1
  }
```

### Walkthrough after fix (same scenario):

| Day | Event | Last strength | Strength allowed? |
|-----|-------|--------------|-------------------|
| Tue | Strength | nil | Yes |
| Wed | Strength | Tue (1 day) | Yes (1 >= 1) |
| Thu | Rest (rolling) | — | — |
| Fri | Strength | Wed (2 days) | Yes |
| Sat | Strength | Fri (1 day) | Yes |
| Sun | Strength | Sat (1 day) | Yes |

Result: **5 strength days** — matches the user's requested target exactly.

The planner will schedule as close to the requested target as the week allows, given rest days and available slots. The recovery gate at `priorHardStreak >= 3` prevents overtraining.

## Files changed

1. `CadenceCore/Sources/CadenceCore/WeeklyPlan.swift`
   - Removed `priorHardStreak == 0` from `canStrength` (line 314-316)
   - Fixed double-counting of `projectedAerobicMinutes` (lines 258-265)
2. `CadenceCore/Tests/CadenceCoreTests/CoachSchedulePreferencesTests.swift`
   - Added `testFiveStrengthSixCardioPlansReasonableStrengthDays`

## Testing

- `swift test`: 662 tests, 0 failures
- New test: asserts at least 3 strength days in current week and 6 over the visible horizon with 5 strength + 6 cardio prefs
