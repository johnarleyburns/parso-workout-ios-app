# Expanded iPhone Set Entry — Design and Agentic Coder Handoff

## Status and intent

This document is an implementation handoff, not an implementation. The interactive reference is docs/expanded-set-entry-mockups.html.

Do not begin by improvising a new layout. Open the mockup in a browser, click through every page, and treat its visual order, control hierarchy, and hit-target philosophy as the implementation target.

## Product goal

Replace the cramped iPhone inline set editor with a full-screen set-entry and set-edit experience that is easy to use while tired, breathing hard, or handling the phone with sweaty or chalky hands.

Opening either “add set” or an existing set should present the same expanded editor. The only differences are initial values, title/action copy, and the availability of a guarded delete action.

The fixed information order is:

1. Exercise name
2. Set number
3. Weight and weight adjustments
4. Reps
5. RPE/RIR mode
6. RPE/RIR number
7. Save and Cancel

Do not turn this into a multi-step wizard. All primary values must remain visible in one full-screen presentation so the lifter can review the complete set before saving.

## Interaction principles

### Built for compromised dexterity

- Treat 56 pt as the preferred minimum height for primary controls.
- Never create a hit target smaller than 44 × 44 pt.
- Keep at least 8 pt between adjacent destructive/confirming actions and at least 6 pt between non-destructive value buttons.
- Avoid icon-only controls for the primary flow. Minus and plus may use symbols because their meaning is universal, but weight buttons should also show the active increment, such as “− 5 lb” and “+ 5 lb.”
- Every tap must produce immediate visual state change. Add light haptics for increments and mode/value selection, stronger success haptics for Save, and warning haptics only for confirmed deletion.
- Do not depend on swipe, long press, context menu, hover, or precision dragging for any required action.

### One-hand rhythm

- Keep the large adjustment controls in stable positions as values change.
- Keep Save pinned above the bottom safe area.
- Cancel must be available both as the leading navigation action and in the fixed footer. The duplicate is intentional: the top action follows iOS convention; the large footer action serves the gym context.
- Preserve entered values while scrolling and while presenting the direct-entry keypad.
- Do not auto-dismiss merely because a value changed.

### Defaults reduce taps

- New set defaults should follow the existing plan/previous-set behavior.
- Edit mode must preload the exact stored weight, reps, performer, bodyweight state, and effort.
- Remember the lifter’s last-used RPE/RIR display mode for subsequent sets in the current workout.
- Effort is optional. None is a first-class visible selection.

## Screen anatomy

### Header

- Present with fullScreenCover, not an inline row and not a partial-height sheet.
- Show the exercise name centered with one-line truncation and Dynamic Type scaling.
- Show “Set N of M” for a planned/new set.
- Show “Editing set N” for an existing set.
- Show Cancel as a minimum 44 × 44 pt leading action.
- In edit mode, place Delete at the trailing edge. It must open a confirmation dialog that names the exercise and set number.
- If a partner is selected, show a clearly labeled performer chip in the context area. Tapping it may open a separate large roster sheet.

### Context line

- New set: show the immediately previous set when available, for example “Last set 225 lb × 5 · RPE 8.”
- Edit set: show recorded time or a concise “Recorded” state.
- Context is secondary and may disappear at very large accessibility text sizes before primary controls are compressed.

### Weight

- Show the current weight as the largest number on the screen, with monospaced digits and the unit adjacent.
- Preserve quarter-unit display precision.
- Tapping the weight value or Type… opens direct numeric entry using the existing keypad behavior.
- Provide familiar increment options:
  - Pounds: 45, 35, 25, 10, 5, 2.5, 0.25.
  - Kilograms: use the project’s established metric plate increments, retaining 0.25 precision where supported.
- One increment is selected at a time.
- Large minus/plus buttons apply the selected increment and include the amount in their label.
- Clamp weight at zero and at the domain maximum; never wrap.
- Do not silently round an exact manually entered value when the user later changes reps or effort.
- For a bodyweight exercise, rename the section to Added weight, explicitly explain that the value is added load, and allow zero.

The implementing agent must verify whether the existing domain treats logged weight as total load or per-side load and preserve that meaning. Do not change the data model’s semantics as part of this UI project.

### Reps

- Use a large minus, monospaced value, and plus row.
- Target range is 1–100 unless existing domain rules are narrower.
- A single tap changes one rep.
- Long-press acceleration is optional and must not replace single taps.
- VoiceOver labels must say “Decrease reps,” “5 reps,” and “Increase reps.”

### Effort mode

- Show a two-segment RPE/RIR control at all times.
- Use the shared WatchEffortMode semantics so iPhone and Watch agree.
- Switching modes changes presentation, not the underlying meaning of an already selected effort. Convert the current canonical value rather than discarding it when possible.
- Persist canonical RPE in the current data model unless a separate product decision changes storage.

### Effort value

- Show None plus direct numeric choices without a context menu.
- Values must be large buttons and clearly selected.
- RPE copy:
  - 10: maximum effort, no reps left.
  - 9: very hard, about 1 rep left.
  - 8: hard, about 2 reps left.
  - 7: challenging, about 3 reps left.
  - Lower values: comfortable effort.
- RIR copy states the selected number of good reps remaining.
- Keep the plain-language helper below the number grid. This helps newer lifters and lets experienced lifters ignore it.
- Because the current shared conversion clamps to 1–10, do not add RIR 0 without first updating and testing the shared effort contract. Raise this as a product decision if zero RIR is desired.

### Footer

- Pin a large footer above the safe area.
- Cancel is secondary; Save is the widest, highest-emphasis action.
- Copy:
  - Add mode: Save set
  - Edit mode: Save changes
- Disable Save only for invalid required values. Missing effort must not disable it.
- Save should be idempotent while a write is in flight and should show progress without moving the control.
- On successful save, dismiss and return focus/scroll position to the originating exercise card.

## Visual language

- Follow the app’s native system background and Dynamic Type behavior rather than hard-coding the mockup’s pixel values.
- Use green for selected controls and Save, matching the Watch set-entry success action.
- Use orange only for PR/warm-up emphasis; use red only for delete/irreversible confirmation.
- Use rounded cards and controls with strong separation in dark and light mode.
- Keep secondary text quiet enough that weight/reps/effort remain the visual spine.
- Respect Reduce Motion, Increase Contrast, Bold Text, and Differentiate Without Color.

## Required states

Implement and preview at least these states:

1. New planned set with previous-set context and no effort selected.
2. New unplanned set with clean defaults.
3. Edit existing set with quarter-unit weight and stored RPE.
4. RIR display mode with a selected value.
5. Bodyweight exercise with zero and positive added load.
6. Partner-attributed set.
7. Would-be PR indication.
8. Invalid direct weight entry.
9. Save in progress.
10. Delete confirmation.
11. Accessibility text at the largest supported size.
12. Compact iPhone height and landscape behavior, even if landscape is intentionally constrained.

## Suggested implementation shape

These names are suggestions; preserve repository conventions if nearby code provides a better fit.

- Introduce a single app-only ExpandedSetEditorView.
- Present it from the session level through one identifiable SetEditorRoute using fullScreenCover(item:).
- Route cases should distinguish adding a set from editing a concrete set ID without duplicating view code.
- Put draft mutations in a small observable/editor model so buttons, conversion, validation, and save-in-flight behavior are independently testable.
- Reuse SetDraft, InlineEditorConfig, shared unit conversion, quarter-unit formatting, WatchEffortMode, PR calculation, and performer roster models.
- Keep persistence in the existing session/repository owner. The editor should emit a validated draft and should not create a second data-writing path.
- Retire the required-path use of InlineSetEditorView after the expanded flow is verified. Do not leave two competing set-entry experiences reachable from the same workout screen.
- Reuse or extract the direct numeric keypad from WeightKeypadSheet; avoid maintaining two subtly different keypad parsers.

Likely integration points to inspect before editing:

- Cadence/Cadence/Features/Train/ExerciseCardView.swift
- Cadence/Cadence/Features/Train/InlineSetEditorView.swift
- Cadence/Cadence/Features/Train/WeightKeypadSheet.swift
- Cadence/Cadence/Features/Train/SessionView.swift
- Cadence/Cadence/Features/Train/SessionViewShared.swift
- CadenceCore/Sources/CadenceFeatures/WatchStrengthSettings.swift
- CadenceCore/Sources/CadenceFeatures/Format.swift

## Data and conversion rules

- Weight input remains in the user’s selected display unit and converts to canonical kilograms exactly once at the boundary.
- Display formatting rounds to the nearest 0.25 only where the product currently calls for it; never repeatedly convert and round the draft during editing.
- Reps are integer values.
- RPE is optional canonical state.
- RIR is a display/input mode converted through WatchEffortMode.
- Cancel must discard the draft without mutating the stored set.
- Edit Save updates the existing set identity; it must not append a replacement set.
- Add Save creates exactly one set even if the user double taps.
- Delete is edit-only and preserves existing session invariants and sync behavior.

## Accessibility contract

Add stable identifiers rather than relying on localized labels:

- setEditor.fullScreen
- setEditor.exerciseName
- setEditor.setNumber
- setEditor.weightValue
- setEditor.weight.minus
- setEditor.weight.plus
- setEditor.weight.increment.45 and corresponding options
- setEditor.weight.type
- setEditor.reps.minus
- setEditor.reps.value
- setEditor.reps.plus
- setEditor.effort.rpe
- setEditor.effort.rir
- setEditor.effort.none
- setEditor.effort.value.1 through .10
- setEditor.cancel
- setEditor.save
- setEditor.delete

VoiceOver order must follow the visual order defined above. Selected increment, effort mode, and effort value must expose selected state. Do not announce every decorative helper.

## Unit tests

Add or expand unit tests for:

- Increment selection and exact plus/minus behavior for every pound and kilogram option.
- Zero clamping and domain maximum clamping.
- Quarter-unit manual input remains stable through unrelated draft mutations.
- Reps lower and upper bounds.
- RPE-to-RIR and RIR-to-canonical-RPE behavior.
- Switching effort mode preserves equivalent effort where representable.
- None clears effort and does not block Save.
- Bodyweight zero added load is valid.
- Add Save emits one draft.
- Edit Save preserves set identity.
- Double-tap/save-in-flight cannot emit duplicate writes.
- Cancel emits no mutation.

## iPhone UI smoke additions

Extend the iPhone strength smoke test with a focused expanded-editor path:

1. Tap Add Set and assert setEditor.fullScreen exists.
2. Assert exercise name and set number.
3. Select the 5 lb increment, add weight, and verify the updated accessibility value.
4. Decrement and increment reps.
5. Switch to RIR and select a value.
6. Save and verify the completed row reflects weight, reps, and equivalent effort.
7. Reopen that completed row in edit mode.
8. Change weight by 0.25 and save changes.
9. Verify the same row was updated rather than duplicated.
10. Open a fresh set, change values, cancel, and verify no set was added.

Add a separate accessibility smoke assertion for tappable frame sizes if the project’s UI-test helpers support geometry checks. Manual testing on a small iPhone remains required because simulator automation does not reproduce sweat, grip, or thumb occlusion.

## Manual acceptance

- Complete three sets one-handed without using direct keypad entry.
- Enter a nonstandard quarter-unit load with the keypad.
- Correct a previously logged set without creating a duplicate.
- Change between RPE and RIR and verify the displayed meaning.
- Save with effort unset.
- Cancel after changing every field and verify nothing persisted.
- Test with wet or sweaty fingers or gloves on a physical iPhone using deliberately imprecise taps.
- Test on the smallest supported iPhone and with the largest accessibility text size.
- Test VoiceOver, Reduce Motion, Increase Contrast, and light/dark appearance.

## Out of scope

- Do not redesign the workout session screen outside the tap targets needed to launch the editor.
- Do not change workout programming or set-prescription logic.
- Do not change the Watch set-entry screen.
- Do not add new weight semantics, plate calculators, barbell calculators, velocity tracking, or automatic RPE prediction.
- Do not implement the Widget Extension work as part of this UI task.

## Agent completion protocol

The implementation agent must:

1. Write a scoped implementation plan before modifying Swift.
2. Compare the existing app and Watch behavior against this document.
3. Implement the expanded editor and route all add/edit entry points through it.
4. Add unit and iPhone UI smoke coverage.
5. Run repository guardrails, SwiftPM tests, iPhone build-for-testing, and the focused iPhone smoke test.
6. Review the final diff against every requirement and required state above.
7. Update README/current state only after behavior is verified.
8. Report any deliberate deviation from the mockup with rationale; do not silently omit controls or shrink hit targets to make the layout fit.

## Definition of done

- Add and edit both open the same full-screen editor.
- Exercise, set number, weight, reps, effort mode/value, Save, and Cancel follow the specified order.
- Required actions have large, forgiving hit targets.
- Weight increments include the requested gym-friendly values and preserve quarter-unit precision.
- RPE/RIR entry is visible and fully operable without menus.
- Bodyweight and partner states remain understandable.
- Unit, UI smoke, accessibility, and manual acceptance checks pass.
- No required set-entry action depends on the old cramped inline interface.
