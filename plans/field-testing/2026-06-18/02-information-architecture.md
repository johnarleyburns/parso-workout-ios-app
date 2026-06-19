# P2 — Information Architecture (Workout / Tests / Progress)

**Branch:** `p2/information-architecture` off `main`
**Risk:** Medium (UI plumbing, tab restructure, UI test migration)
**Depends on:** nothing (independent of P1)

---

## Problem

Current tab bar is Workout / Plan / Library. The pivot to a coach-driven app requires:
- Tests as a first-class tab (not buried in Plan)
- Progress (history + trends) as a first-class tab
- Planning (routines/programs) inside Workout, not a separate tab
- Library's exercise browser unified with the existing ExercisePickerView

## What the Code Does Today

### RootTabView.swift (25 lines)
```
enum Tab: Hashable { case workout, plan, library }
```
Three tabs: HomeView (Workout), PlanView (Plan), LibraryView (Library).

### LibraryView.swift (267 lines)
Two-segment picker:
- **Exercises:** body-part filter chips, popular/grouped/search modes, links to ExerciseDetailView.
  Uses `ExerciseLibrary`, `BodyPart`, search/filter. Rich affordances: chips, subtitles, detail.
- **Routines:** grouped preset sections (5x5, Splits, Calisthenics, Olympic) from
  `StrengthPresets.all` + user `SessionTemplate` list + "New Template" button.
  Links to `RoutineDetailView` (which has `switchToWorkout` callback).

Accessibility IDs: `library`, `library.browseAll`, `library.filter.*`, `library.exercise.*`,
`library.routine.*`, `library.template.*`, `library.newTemplate`.

### PlanView.swift (107 lines)
Shows assessment battery: queries `Assessment`, computes `AssessmentSummary`, lists all
`AssessmentKind` grouped by `AssessmentCategory`. Links to `AssessmentDetailView(kind:)`.
Accessibility IDs: `plan.assessments.intro`, `plan.assessments.list`, `plan.assessment.<kind>`.

### ExercisePickerView.swift (in Features/Train/)
In-session exercise picker, already wired into SessionView (~lines 303/316). Simpler than
LibraryView's exercise browser — lacks body-part chips, popular-first, muscle subtitles.

### HistoryView.swift (in Features/History/)
Workout history list. Currently reached from HomeView, not a tab.

## Design

### New Tab Structure

```
RootTabView
├── Workout (tab.workout) — HomeView
│   ├── Hero → strength workout start
│   ├── Secondary → cardio start
│   ├── [NEW] Programs & Routines section/button
│   │   └── PlanningView (relocated from Library's Routines segment)
│   │       ├── Preset groups (StrengthPresets.all)
│   │       ├── User templates (SessionTemplate)
│   │       ├── "New Template" button
│   │       └── RoutineDetailView (with switchToWorkout)
│   └── Coach cards, insights (existing)
│
├── Tests (tab.tests) — TestsView (promoted from PlanView)
│   ├── "Your fitness" baseline header (shell in P2, real content P3)
│   ├── Assessment battery list (from PlanView)
│   └── AssessmentDetailView, RecordAssessmentView (existing)
│
└── Progress (tab.progress) — ProgressView
    ├── HistoryView content (promoted from Features/History/)
    └── [P3] Test-result trends section
```

### Step-by-Step Migration

**Phase 2a — Stand up new tabs (additive)**
1. Create `TestsView.swift` — extract PlanView's assessment content into this new view.
   Title: "Tests". `accessibilityIdentifier("tests")`.
2. Create `ProgressView.swift` — wraps HistoryView content. Title: "Progress".
   `accessibilityIdentifier("progress")`.
3. Create `PlanningView.swift` — extract LibraryView's Routines segment. Receives
   `switchToWorkout` callback. `accessibilityIdentifier("planning")`.
4. Add "Programs & Routines" navigation entry to HomeView → pushes PlanningView.
5. Update `RootTabView`:
   ```swift
   enum Tab: Hashable { case workout, tests, progress }
   ```
   Wire: HomeView (Workout), TestsView (Tests), ProgressView (Progress).
   New accessibility IDs: `tab.tests`, `tab.progress`.

**Phase 2b — Unify exercise browser**
1. Enhance `ExercisePickerView` (or create `UnifiedExerciseBrowser`) with LibraryView's
   richer affordances: body-part chips, popular-first sorting, muscle subtitles, detail view.
2. Present unified browser from:
   - In-session "add exercise" (SessionView — already uses ExercisePickerView)
   - Planning/routine surface (PlanningView — for substitutions)
3. Test both presentation contexts.

**Phase 2c — Remove old tabs (subtractive)**
1. Remove `Tab.plan` and `Tab.library` from RootTabView.
2. Delete or stub `LibraryView.swift` (after verifying all content is relocated).
3. Keep `PlanView.swift` content alive in `TestsView.swift`.
4. Fix broken imports/references.

**Phase 2d — UI test migration**
Update accessibility identifiers in UI tests:
- `plan.assessments.list` → `tests.assessments.list`
- `plan.assessment.*` → `tests.assessment.*`
- `plan.assessments.intro` → `tests.assessments.intro`
- `plan.preview.start` — check if this is assessment-related or workout-plan-related;
  relocate accordingly.
- `library.placeholder` → remove or relocate.
- `tab.plan` → `tab.tests`
- `tab.library` → `tab.progress`

Files needing updates:
- `P4AssessmentsUITests.swift` — `plan.assessments.list`, `plan.assessment.pushupMax`, `plan.assessment.e1RM`
- `P3CoachHomeUITests.swift` — `plan.assessments.list`, `library.placeholder`
- `FR10Feedback3UITests.swift` — `plan.preview.start`
- `FR7LifecycleUITests.swift` — `plan.preview.start`

## Data Model Deltas

None. Pure UI restructure.

## Implementation Steps

1. Create `Cadence/Cadence/Features/Tests/TestsView.swift` — extract from PlanView
2. Create `Cadence/Cadence/Features/Progress/ProgressView.swift` — wrap HistoryView
3. Create `Cadence/Cadence/Features/Home/PlanningView.swift` — extract from LibraryView Routines
4. Add planning entry to HomeView
5. Update RootTabView: 3 new tabs, remove old
6. Enhance ExercisePickerView with LibraryView's affordances (body-part chips, popular-first, subtitles)
7. Wire unified browser into PlanningView
8. Update UI test accessibility IDs
9. Remove LibraryView.swift, clean up PlanView.swift
10. Add new files to pbxproj
11. `cd CadenceCore && swift test`
12. `xcodebuild build`
13. Run UI test suite, report results

## Testing

- All existing `swift test` must pass (no CadenceCore changes).
- `xcodebuild build` must pass.
- UI tests: migrate IDs, verify P4AssessmentsUITests + P3CoachHomeUITests pass with new structure.
- Manual: verify tab navigation, planning surface reachable from Workout, exercise browser
  works in both contexts (in-session + planning).
- Accessibility: VoiceOver + Dynamic Type on TestsView, ProgressView, PlanningView.
