# Settings & Workflow Redesign Plan

**Status:** Ready to implement  
**Date:** 2026-06-28  
**Target:** Single PR, phased implementation

---

## Overview

Restructure the app so per-workout settings live on pre-workout setup screens (not in main Settings), remembered per workout type and reused. Move coach settings out of Settings and onto Home's Coach panel. Remove the steps display from Home and put it in "Your Plan" with an adjustable target. Show "Planned (next week)" when this week is empty.

---

## Phase 1: Remove steps from HomeView, move to YourWeekView, add adjustable step target

### 1.1 Remove `stepHealthSection` from HomeView
- Remove the `stepHealthSection` computed property and its usage from `HomeView.body`
- Remove `activityTrend` state variable from `HomeView` (clean up)
- Remove activityTrend fetching from `.task` and `.refreshable`
- Remove `stepSummary` usage from `CoachFacts.make` in `coachDecision` computed property
- The step health data is still computed (StepActivitySummary) but no longer surfaced on Home

### 1.2 Add step health to YourWeekView
- In `YourWeekView`, add a section between "This Week So Far" and "Planned (next week)"
- Show: today's steps, 7-day avg, status badge (low/building/onTrack)
- Show a stepper to adjust daily step target (default 8,000, range 2,000-20,000, step 500)
- Store the user's step target in `CoachSchedulePreferences` as `dailyStepTarget: Int` (default 8,000)
- When the user adjusts, update `StepActivitySummary` thresholds to use their target
- Add citation link for the evidence

### 1.3 Update StepActivitySummary to accept custom target
- Add `init(from:targetDailySteps:)` overload
- `floorDailySteps` is always fixed at 4,000 (evidence-based floor, not adjustable)
- Only `targetDailySteps` and `status` computation use the user's preference

### 1.4 Update CoachSchedulePreferences model
- Add `var dailyStepTarget: Int` (default 8,000)
- Add `withDailyStepTarget(_:)` constrained setter
- The stair-step target range: 2,000-20,000, step 500

### 1.5 YourWeekView data flow
- `YourWeekView` already receives `facts: CoachFacts` and `preferences: CoachSchedulePreferences`
- Need to add `activityTrend: [DayActivity]` parameter
- OR: compute `StepActivitySummary(from: activityTrend, targetDailySteps: preferences.dailyStepTarget)`
- Pass `activityTrend` from `HomeView` when pushing `.yourPlan` route

---

## Phase 2: Show "Planned (next week)" when "rest of week" is empty

### 2.1 Update `plannedRestOfWeekSection` on HomeView
- When `restOfWeekDays` is empty, show "Planned (next week)" section
- Use `coachPlan.nextWeekDays` to populate
- Same visual style as the current section, just with "Next week" header
- If both are empty, show "No more planned sessions" as before

### 2.2 Current behavior
- `restOfWeekDays` = `coachPlan.remainingCalendarWeekDays.filter { !$0.sessions.isEmpty }`
- `coachPlan.nextWeekDays` already computed in WeeklyPlan

---

## Phase 3: Move Coach settings from SettingsView to CoachDecisionCardView

### 3.1 Remove "Coach" section from SettingsView
- Delete the Coach section (Training Goal picker, Experience picker, Schedule Preferences link)

### 3.2 Create CoachContextSettingsView (new file)
- A sheet view accessible from the gear icon on CoachDecisionCardView
- Contains:
  - Training Goal picker (hypertrophy/strength/endurance/power/general)
  - Experience Level picker (beginner/intermediate/advanced)
  - NavigationLink to CoachSchedulePreferencesView
  - Daily step target stepper (2,000-20,000, step 500, default 8,000)
- Footer: "Your coach uses these to tailor insights. Coaching only, not medical advice."

### 3.3 Update CoachDecisionCardView
- The gear icon already calls `onPreferences()` which currently opens `CoachSchedulePreferencesView`
- Change `onPreferences()` to present `CoachContextSettingsView` as a sheet
- The sheet includes a NavigationLink to open `CoachSchedulePreferencesView` for schedule-specific settings

### 3.4 Update HomeView
- Change `onPreferences: { path.append(HomeRoute.coachPreferences) }` to `onPreferences: { showCoachSettings = true }`
- Add `@State private var showCoachSettings = false`
- Add `.sheet(isPresented: $showCoachSettings) { CoachContextSettingsView() }`

---

## Phase 4: Remove per-workout settings from SettingsView, add to pre-workout screens

### What to REMOVE from SettingsView:
- "Workout" section (Rest timer, Auto-start rest timer)
- "Workout start" section (Get-ready countdown)
- "Idle Auto-End" section (toggle + timeout)
- "Strength" section (Round weights to nearest plate)
- "Cardio" section (GPS, auto-pause)
- "Intervals" section (color-blind palette, spoken announcements)
- "Goals" section (weekly cardio goal)
- "Warm-up & Cool-down" section

### What to KEEP in SettingsView:
- "Units & Records" section (weight unit, PR rule, 1RM formula)
- "Health & Sensors" section (Apple Health, auto-save, last sync, HRM)
- "Data" section (Import Workout Log, Backup & Restore)
- "Sounds" section (workout sounds)
- "About" section
- "Support" section

### 4.1 Create `WorkoutSettings` struct (in CadenceCore)
```swift
public struct WorkoutSettings: Codable, Equatable, Sendable {
    public var restSeconds: Int = 90
    public var autoStartRest: Bool = true
    public var preWorkoutCountdown: Int = 10
    public var autoEndOnIdle: Bool = true
    public var idleTimeoutMinutes: Int = 10
    public var plateRounding: Bool = false
    public var gpsHighAccuracy: Bool = false
    public var autoPause: Bool = false
    public var intervalColorBlind: Bool = false
    public var spokenCues: Bool = false
    public var weeklyCardioMinutesGoal: Int = 250
    public var warmupMinutes: Int = 5
    public var cooldownMinutes: Int = 5
    public var useHRMonitoring: Bool = false
}
```

### 4.2 Per-workout-type memory (in AppSettings)
- Store the last-used `WorkoutSettings` per workout type
- Keyed by workout category: "strength", "cardio", "interval"
- On each pre-workout screen, load the last-used settings for that type
- Save settings when the user starts the workout

### 4.3 Create `WorkoutSetupSheet` (reusable pre-workout settings component)
- A shared view that shows the relevant settings for the workout type
- Used in: WeightsStartView, CardioGoalSheet, IntervalSetupView, TimerCardioSetupView, SwimRecordView
- **Strength settings**: rest timer, auto-start rest, countdown, warm-up, cool-down, HR, plate rounding, idle auto-end (toggle + timeout)
- **Cardio settings**: countdown, HR, GPS accuracy, auto-pause, distance goal (already exists)
- **Interval settings**: countdown, HR, color-blind palette, spoken cues, warm-up, cool-down
- Each screen maintains its own @State for settings, initialized from stored defaults, saved on "Start"

### 4.4 Update existing pre-workout screens

**WeightsStartView / WorkoutPlanEditor:**
- Already has warm-up, cool-down, HR monitoring steppers/toggles
- Add: rest timer, auto-start rest, countdown, plate rounding, idle auto-end toggle + timeout
- Load from `settings.lastStrengthSettings` on appear
- Save to `settings.lastStrengthSettings` on start

**CardioGoalSheet / TimerCardioSetupView:**
- Already has distance goal + HR toggle
- Add: countdown, GPS accuracy (for outdoor), auto-pause (for outdoor)
- Load from `settings.lastCardioSettings`
- Save on start

**IntervalSetupView:**
- Already has warm-up, cool-down, HR toggle
- Add: countdown, color-blind palette, spoken cues
- Load from `settings.lastIntervalSettings`
- Save on start

**SwimRecordView:**
- Already has target laps, HR toggle
- Add: countdown
- Load from `settings.lastCardioSettings` (swim is cardio)
- Save on start

### 4.5 ALWAYS show settings before workout
- Currently, some paths skip settings (e.g., "Quick Start" from WeightsStartView opens WorkoutPlanEditor but doesn't show settings)
- New rule: EVERY workout launch path (whether from Home quick actions, Coach card, or alternative picker) MUST show a settings screen first
- Even "Quick Start" shows WorkoutPlanEditor (which now has full settings)
- Even "Just start" from cardio shows CardioGoalSheet (which now has settings)
- Remove any code path that starts a workout directly

---

## Phase 5: Per-workout Settings Memory Implementation

### 5.1 AppSettings additions
```swift
// Per-workout-type settings memory
var lastStrengthSettings: WorkoutSettings
var lastCardioSettings: WorkoutSettings
var lastIntervalSettings: WorkoutSettings
```
- Persisted as JSON in UserDefaults, one key per type
- Loaded on first access, saved whenever a workout starts
- Default values match current SettingsDefault values

### 5.2 Flow for each workout type

**Strength:**
1. User taps "Start" from Coach card or quick action
2. → WeightsStartView shows (already the case)
3. → User picks an option (Quick Start, Warm-Up, Previous, Library)
4. → WorkoutPlanEditor shows with full settings pre-populated from lastStrengthSettings
5. → User adjusts settings → taps "Start"
6. → Settings saved to lastStrengthSettings
7. → HR gate → countdown → warm-up (if selected) → SessionView

**Cardio (outdoor):**
1. User taps "Start" from Coach card or quick action
2. → CardioGoalSheet shows with settings: distance goal + HR + countdown + GPS + auto-pause
3. → User adjusts → taps "Start"
4. → Settings saved to lastCardioSettings
5. → HR gate → countdown → OutdoorCardioView

**Cardio (timer):**
1. → TimerCardioSetupView with settings: suggested duration + HR + countdown
2. → User adjusts → taps "Start"
3. → Settings saved to lastCardioSettings
4. → HR gate → countdown → RecordCardioView

**Intervals:**
1. → IntervalSetupView with settings: preset/custom + HR + countdown + color-blind + spoken cues
2. → User adjusts → taps "Start"
3. → Settings saved to lastIntervalSettings
4. → IntervalView

**Swim:**
1. → SwimRecordView setup screen with: target laps + HR + countdown
2. → User adjusts → taps "Start"
3. → Settings saved to lastCardioSettings (swim is cardio)
4. → Swim recording starts

---

## Phase 6: Clean up AppSettings backward compatibility

### 6.1 Keep in AppSettings but no longer in SettingsView UI
- `restSeconds`, `autoStartRest`, `preWorkoutCountdown` — keep for backward compat with old exports
- `idleTimeoutMinutes`, `autoEndOnIdle`, `plateRounding`, `gpsHighAccuracy`, `autoPause`
- `intervalColorBlind`, `spokenCues`, `weeklyCardioMinutesGoal`, `warmupMinutes`, `cooldownMinutes`
- `useHRMonitoring`, `workoutSounds`

These properties remain in AppSettings for:
- Importing from older exports
- SessionView still reads from them directly in some cases
- They become the "factory defaults" — used ONLY when no per-type settings have been saved yet

### 6.2 ExportPreferences
- Keep all fields in ExportPreferences for backward compat
- Still decode `stepGoal` and other removed fields

---

## Files Changed

| File | Change |
|------|--------|
| `CadenceCore/Sources/CadenceCore/WorkoutSettings.swift` | NEW: WorkoutSettings struct |
| `CadenceCore/Sources/CadenceCore/CoachSchedulePreferences.swift` | ADD: dailyStepTarget property |
| `CadenceCore/Sources/CadenceCore/Services.swift` | UPDATE: StepActivitySummary with target overload |
| `Cadence/Cadence/App/AppSettings.swift` | ADD: per-type WorkoutSettings storage, remove coach props de-emphasis |
| `Cadence/Cadence/Features/Settings/SettingsView.swift` | REMOVE: Coach, Workout, Workout Start, Idle Auto-End, Strength, Cardio, Intervals, Goals, Warm-up |
| `Cadence/Cadence/Features/Coach/CoachContextSettingsView.swift` | NEW: coach context settings sheet |
| `Cadence/Cadence/Features/Coach/CoachDecisionCardView.swift` | UPDATE: gear button opens coach context settings |
| `Cadence/Cadence/Features/Coach/YourWeekView.swift` | ADD: step health section, step target stepper |
| `Cadence/Cadence/Features/Home/HomeView.swift` | REMOVE: stepHealthSection, activityTrend; ADD: next week planning; UPDATE: coach prefs flow; ADD: per-type settings passthrough |
| `Cadence/Cadence/Features/Home/WorkoutPlanEditor.swift` | ADD: full settings controls |
| `Cadence/Cadence/Features/Cardio/CardioGoalSheet.swift` | ADD: full settings controls |
| `Cadence/Cadence/Features/Cardio/TimerCardioSetupView.swift` | ADD: full settings controls |
| `Cadence/Cadence/Features/Intervals/IntervalSetupView.swift` | ADD: full settings controls |
| `Cadence/Cadence/Features/Cardio/SwimRecordView.swift` | ADD: countdown setting |
| `Cadence/Cadence/Features/Train/SessionView.swift` | READ: from per-type settings where applicable |

---

## Test Plan

### Unit tests (CadenceCore)
1. `WorkoutSettings` Codable round-trip
2. `CoachSchedulePreferences.dailyStepTarget` default + constraints
3. `StepActivitySummary(from:targetDailySteps:)` with custom target
4. Legacy `ExportPreferences` with removed fields still decodes

### UI verification
1. HomeView: no steps section, Coach gear opens coach settings sheet
2. SettingsView: only Units & Records, Health & Sensors, Data, Sounds, About, Support
3. YourWeekView: step health status + adjustable target
4. HomeView: "Planned (next week)" shown when rest of week empty
5. Every workout launch path shows settings first
6. Per-type settings are remembered between sessions

---

## Implementation Order

1. Create `WorkoutSettings` struct in CadenceCore
2. Add `dailyStepTarget` to `CoachSchedulePreferences`
3. Update `StepActivitySummary` with target overload
4. Remove steps from HomeView
5. Add steps to YourWeekView
6. Show next week when rest of week empty on HomeView
7. Create `CoachContextSettingsView`
8. Update CoachDecisionCardView and HomeView for coach settings
9. Add per-type settings storage to AppSettings
10. Update WorkoutPlanEditor with full settings
11. Update CardioGoalSheet with full settings
12. Update TimerCardioSetupView with full settings
13. Update IntervalSetupView with full settings
14. Update SwimRecordView with countdown
15. Clean up SettingsView (remove moved sections)
16. Ensure every workout path shows settings
17. Write tests
18. Verify build + tests
