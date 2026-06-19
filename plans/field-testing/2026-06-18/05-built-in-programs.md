# P5 — Built-In Programs (Self-Directed Alternative)

**Branch:** `p5/built-in-programs` (stacks on P2)
**Risk:** Low
**Depends on:** P2 (planning surface must live in Workout tab)

---

## Problem

StrengthPresets has 17 plans across 4 categories (5x5, Splits, Calisthenics, Olympic) but
is missing several widely-known, well-regarded programs. Users who prefer to follow a
published program (rather than coach-generated prescriptions) need these available from the
in-Workout planning surface.

## What the Code Does Today

### WorkoutPlan.swift — StrengthPresets.all (17 plans)

**5x5 (4 plans):**
- Classic 5x5 (Workout A, Workout B)
- Intermediate 5x5 (Workout A, Workout B)

**Splits (7 plans):**
- Upper Body, Lower Body
- Push Day, Pull Day, Legs Day
- Chest & Triceps, Back & Biceps

**Calisthenics (3 plans):**
- Beginner Bodyweight
- Intermediate Calisthenics
- Advanced Gymnastics Strength

**Olympic (3 plans):**
- Clean & Jerk Complex
- Snatch Development
- Olympic Pulling Accessories

### Missing Widely-Known Programs

- **5/3/1 (Wendler):** 4-week mesocycle, main lifts at prescribed %1RM, AMRAP on last set.
  One of the most popular intermediate programs. Ties directly to e1RM baselines (P3/P4).
- **GZCLP:** tiered structure (T1/T2/T3), linear progression, well-suited for late
  beginners / early intermediates.
- **nSuns 5/3/1 LP:** high-volume 5/3/1 variant with prescribed percentages per set.
  Very popular on Reddit. Requires e1RM baselines.
- **PPL (Reddit PPL / Metallicadpa):** 6-day Push/Pull/Legs split, the most recommended
  beginner program on r/Fitness. We have push/pull/legs days but not the specific
  Reddit PPL structure.

### WorkoutPlan / PlanItem Structure

```swift
struct PlanItem: Codable, Identifiable, Hashable {
    let movement: String
    var reps: Int
    var distanceM: Double?
    var loadLb: Int?
    var targetSets: Int
    var note: String
}
```

`loadLb` is optional — for percentage-based programs, we can leave it nil and let the
coach fill it from e1RM (P4 wiring). Add `loadPercentage: Double?` for %1RM programs.

## Design

### 1. New Programs to Add

**5/3/1 (Wendler) — 4 WorkoutPlans (one per main lift day):**
- Day 1: Squat (5/3/1 sets + AMRAP) + accessories
- Day 2: Bench Press + accessories
- Day 3: Deadlift + accessories
- Day 4: OHP + accessories
- Each day prescribes %1RM: Week 1 (5x65/75/85%), Week 2 (3x70/80/90%),
  Week 3 (5/3/1 at 75/85/95%), Week 4 (deload).
- Note: full periodization requires the coach to cycle weeks — the WorkoutPlan
  represents a single session template; the progression logic lives in P4.

**GZCLP — 4 WorkoutPlans:**
- Day A1: Squat T1 (5x3), OHP T2 (3x10), lat pulldown T3 (3x15+)
- Day B1: Bench T1 (5x3), Deadlift T2 (3x10), row T3 (3x15+)
- Day A2: OHP T1, Squat T2, lat pulldown T3
- Day B2: Deadlift T1, Bench T2, row T3
- Linear progression: add weight when sets complete; if fail, reduce sets and add reps.

**nSuns 5/3/1 LP — 2 WorkoutPlans (4-day or 5-day variant):**
- Extremely high-volume; 8-9 working sets per main lift at prescribed %TM.
- Pair with user-chosen accessories.

**PPL (6-day) — 6 WorkoutPlans:**
- Push A, Pull A, Legs A, Push B, Pull B, Legs B
- Specific exercise selection matching the widely-recommended structure.
- Linear progression on compounds.

### 2. PlanItem Schema Addition (Additive)

Add to `PlanItem`:
```swift
var loadPercentage: Double?  // e.g., 0.85 for 85% of 1RM
```
Optional, defaults to nil. Existing plans unaffected. CloudKit safe.

When `loadPercentage` is set and the user has an e1RM for the movement, the UI computes
and displays the actual load. If no e1RM exists, shows "Set your [exercise] 1RM in
Tests to see prescribed loads."

### 3. StrengthPresets Category Additions

```swift
enum StrengthPresets {
    static var all: [WorkoutPlan] { ... }
    // Add new groups
    static var fiveThreeOne: [WorkoutPlan] { ... }
    static var gzclp: [WorkoutPlan] { ... }
    static var nSuns: [WorkoutPlan] { ... }
    static var ppl: [WorkoutPlan] { ... }
}
```

Group labels in the planning surface:
- 5x5 Programs
- 5/3/1
- GZCLP
- nSuns
- PPL (6-Day)
- Splits
- Calisthenics
- Olympic Lifting

### 4. Original Descriptions

Each program gets an original description (not copyrighted text):
- What it is, who it's for, how it progresses
- Attribute the scheme origin (e.g., "Based on Jim Wendler's 5/3/1 methodology")
- No copyrighted program text verbatim

### 5. Planning Surface Integration

The PlanningView (P2) already groups presets by category. Adding new categories should be
automatic if `StrengthPresets.all` is extended. Verify:
- New program groups appear in the planning surface
- Tapping a program opens RoutineDetailView with the plan's exercises
- "Start Workout" from RoutineDetailView loads the plan into a session
- Unified exercise browser available for substitutions within a plan

## Implementation Steps

1. Add `loadPercentage: Double?` to `PlanItem` (additive, optional)
2. Create 5/3/1 WorkoutPlans (4 sessions)
3. Create GZCLP WorkoutPlans (4 sessions)
4. Create nSuns WorkoutPlans (2 variants)
5. Create PPL WorkoutPlans (6 sessions)
6. Write original descriptions for each
7. Update StrengthPresets to include new groups
8. Verify new programs appear in PlanningView
9. Handle `loadPercentage` display: compute from e1RM or prompt for baseline
10. `cd CadenceCore && swift test`
11. `xcodebuild build`

## Testing

- **Unit tests:** verify new WorkoutPlans are well-formed (non-empty items, valid movements)
- **Unit tests:** loadPercentage computation (100kg e1RM * 0.85 = 85kg)
- `xcodebuild build`
- Manual: verify new programs appear in planning surface, can be started as workouts
- Accessibility: all new content has VoiceOver labels
