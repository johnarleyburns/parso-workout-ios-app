# Plan: Coach Two-a-Days and Set Entry Load Accounting

## Summary

Implement the product fixes as one focused strength/cardio planning and set-entry upgrade:

- The Coach box must show every uncompleted planned workout for today, including strength + cardio two-a-days.
- Set entry must support clear optional RPE, smarter weight defaults, contextual info, dumbbell accounting, and barbell bar-weight accounting.
- Calculations, PRs, volume, recommendations, and coach facts must use effective load for new sets while preserving legacy history unchanged.

Default assumptions locked for implementation:

- Barbell main weight entry becomes added plate/load; default bar weight is 45 lb and is added in calculations.
- Dumbbell load accounting is stored as exercise defaults, snapshotted onto sets, and overrideable in set-entry options.
- Two-a-days appear as one stacked Coach card with independent workout rows/buttons.

## Key Changes

### Coach Two-a-Day Recommendations

- Extend CoachDecision with a new ordered list such as todayPlannedRecommendations: [CoachSession].
- Populate it from today's planned sessions, not just the highest-scored primary.
- Include both planned strength and planned cardio when both exist today.
- Filter out only the planned session type that has already been completed:
    - If cardio was completed, strength remains.
    - If strength was completed, cardio remains.
    - Only after both are complete does planAdherence become .planComplete.

- Keep primary for backward compatibility, but make it the first uncompleted planned recommendation when today has planned work.
- Update CoachDecisionCardView:
    - If todayPlannedRecommendations.count > 1, render a "Today's plan" style stack with one row per planned workout.
    - Each row has title, subtitle, modality icon, and its own Start button.
    - Completed rows may show as done only if useful, but uncompleted rows must remain visible/actionable.

- Update HomeView.launchDecision(_:) to launch whichever CoachSession row was tapped.
- Update add-on logic so add-ons appear only when all planned sessions for today are complete.

### Set Entry UX

- Make optional RPE visibly intentional in the inline set editor:
    - Keep SetEntry.rpe optional.
    - Add a compact but discoverable RPE control with clear "none" state.
    - Preserve existing RPE when editing a set unless the user clears/changes it.

- Update first-set weight defaulting:
    - For the first set of an exercise in the current session, default to the first working set weight from the most recent prior session for that same exercise.
    - If no prior working set exists, default to 0.
    - Show an inline info callout when the field is focused/opened: Previously started this exercise at 65 lb.

- Update subsequent-set defaulting:
    - For the second and later sets of the same exercise in the current session, prefill the previous set's entered weight.
    - This should happen before prescription fallback.

- Preserve prescribed coach load behavior only when no current-session previous set exists and no prior starting weight exists, unless the existing prescribed session logic explicitly requires priority.
- Add a weight info button beside the weight field:
    - Barbell/bodyweight message: Enter added load as 0 when using only the bar or bodyweight. Bar weight is added separately for barbell calculations.
    - Dumbbell message: Enter the weight of one dumbbell. The app accounts for paired, single, and isolateral dumbbell movements in calculations.

- Show the dumbbell info callout automatically the first time the user starts a dumbbell exercise, and keep it available through the info button afterward.

### Load Accounting Model and Calculations

- Add CloudKit-safe stored metadata with defaults:
    - On Exercise: load accounting default, default bar weight, default dumbbell multiplier/accounting mode, and user override flag.
    - On SetEntry: snapshotted barWeightKg, loadMultiplier, and load-accounting version/mode.

- Keep SetEntry.weight as the user-entered load in kg.
- Add a computed helper such as SetEntry.effectiveLoadKg:
    - Barbell: (enteredWeightKg + barWeightKg) * multiplier.
    - Bodyweight: entered added load only, with 0 valid.
    - Dual dumbbell: entered one-dumbbell weight times 2.
    - Single dumbbell: entered one-dumbbell weight times 1.
    - Isolateral dumbbell comparison mode: entered one-dumbbell weight times 2.
    - Legacy sets without new metadata: effective load equals existing weight.

- Add set-entry Options for barbell movements:
    - Default bar weight: 45 lb.
    - User can change it per set to values like 30 lb, 100 lb, or 0.

- Seed exercise accounting from existing equipmentValue, isLateral, and known movement names:
    - Barbell and Smith: added load + default 45 lb bar unless Smith/integrated metadata says otherwise.
    - Bodyweight: added load with 0 default.
    - Dumbbell paired movements: one dumbbell entered, multiplier 2.
    - Single dumbbell movements such as skullcrusher/goblet-style movements: multiplier 1.
    - Isolateral dumbbell movements such as dumbbell bent-over row: multiplier 2 for comparison against machine/barbell movements.

- Update calculation call sites to use effective load for new-accounting sets:
    - WorkoutMath helpers where appropriate.
    - PRCalculator.
    - WorkoutRepository PR/trend helpers.
    - TrainingFacts.
    - TrainingEvent.
    - StrengthProgress.
    - WorkoutSummaryData.
    - Workout summary total volume.

- Do not reinterpret old sets globally. Existing history remains numerically stable unless a set is edited and saved with new accounting metadata.
- Include new metadata in export/import so backups preserve bar weight, multiplier, and load-accounting mode.

## Test Plan

### Unit Tests

- Coach two-a-day planned day:
    - Given today has strength and cardio planned, the Coach decision exposes both.
    - Use a deterministic cardio title like Tempo training and a strength title; assert both appear in todayPlannedRecommendations.

- Coach completion filtering:
    - After completing only cardio, strength remains visible/actionable.
    - After completing only strength, cardio remains visible/actionable.
    - After completing both, planAdherence becomes complete and add-ons can appear.

- Optional RPE:
    - Adding a set with no RPE stores nil.
    - Adding a set with RPE stores the selected value.
    - Editing weight/reps preserves or clears RPE only according to explicit user input.

- First-set default:
    - Prior session first working set is 65 lb; new session first set defaults to 65 lb and exposes the "previously started" message.
    - No prior session defaults to 0.

- Subsequent-set default:
    - First set entered at 70 lb; second set for the same exercise prefills 70 lb.

- Info text:
    - Barbell/bodyweight info mentions entering 0 for only-bar/bodyweight work.
    - Dumbbell info says to enter the weight of a single dumbbell.

- Load accounting:
    - Dumbbell bench press entered as 50 lb calculates as 100 lb effective.
    - Single dumbbell skullcrusher entered as 50 lb calculates as 50 lb effective.
    - Isolateral dumbbell bent-over row entered as 50 lb compares as 100 lb effective.
    - Barbell entered as 0 lb with default 45 lb bar calculates as 45 lb effective.
    - Barbell override to 30 lb or 100 lb changes effective load accordingly.
    - Legacy sets without metadata keep effective load equal to stored weight.

### UI Tests

- Coach box scenario from the user report:
    - Seed today with both strength and cardio.
    - Assert Tempo training appears.
    - Assert the strength recommendation also appears in the same Coach box.
    - Complete/start/log one recommendation and return home.
    - Assert the other recommendation remains.

- Set logging:
    - Open inline set entry and verify RPE can be set optionally.
    - Verify first-set prior-starting-weight prefill and callout.
    - Verify second-set previous-weight prefill.
    - Verify barbell/bodyweight info text.
    - Verify first-time dumbbell info appears and the info button can reopen it.
    - Verify barbell options allow changing the bar weight.

## Acceptance Criteria

- A user with planned strength + cardio today never sees only one of them in the Coach box unless the other has already been completed.
- Completing one workout in a two-a-day plan does not hide or complete the other.
- RPE is optional but clearly enterable during set logging.
- Weight entry is faster for multi-set exercises because first and later sets prefill correctly.
- Barbell, bodyweight, and dumbbell instructions are visible at the point of entry.
- Effective-load math matches the new barbell/dumbbell semantics without corrupting old workout history.
