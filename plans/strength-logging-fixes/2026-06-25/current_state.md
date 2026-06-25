# Strength logging / history-edit / coach-UI fixes — 2026-06-25

Branch: `fix/strength-logging-and-coach-ui`. Bug batch reported during strength testing.

## Shipped

### Partners are opt-in (1a / 1b)
- New `CadenceCore/SessionRoster` resolves the session roster: an **empty**
  `activePartnerIDs` now means **solo** (just the owner), not "show everyone".
  Removed the legacy show-all fallback in `SessionView`.
- `SessionView` uses `SessionRoster` for `roster` / `activePartnerPeople` /
  `hasPartners` (now `canAttribute`: partner scoped OR a set already attributed) /
  `attributablePartners` (scoped ∪ already-attributed, so a mis-attributed set can be
  corrected).
- Discoverable **Manage partners** sheet (`partner.manage`) with check/uncheck rows
  (`partner.manage.row.<name>`), add field, Done — visible removal that sticks.
- `WorkoutPlanEditor`: a newly-added partner is auto-selected; section footer notes
  partners are optional (leave unchecked = solo).

### Editing a set's performer (1c / 2a)
- The inline set editor's performer chip is now a tappable `Menu`
  (`inline.performer`) — Me + `attributablePartners`. Works live and when editing
  from history.
- Row context-menu performer picker uses `attributablePartners` and the repo.

### History editing (2b / 2c / 2d)
- **Change exercise**: `exerciseCard` ellipsis menu gains "Change exercise"
  (`exercise.changeExercise.<name>`) → exercise picker →
  `WorkoutRepository.changeExercise(in:from:to:)` moves **all** sets in the card and
  syncs `plannedExerciseNames`.
- **Edit in place**: tapping a logged set's weight/reps swaps that row for the inline
  editor in place (was appended detached at the card bottom → read as "can't edit").
- **No-clobber edits**: `WorkoutRepository.updateSet` gained `exercise` +
  `performedBy` params; `recordInlineSet` no longer hardcodes `isWarmup:false` or
  erases the note. Weight/reps edits preserve warm-up flag, note, RPE.
- `completedSetRow` now `.accessibilityElement(children: .contain)` so its
  weight/reps/performer controls stay individually accessible (a `.contextMenu`
  otherwise collapses the row into one element).

### Coach UI (3 / 4)
- **"Why this won"** rebuilt as compact rows matching "What you did": category icon +
  claim title + tappable citation subtitle (HARD RULE preserved) + trailing category
  tag, in a single card. `whyToday.claim.<id>`.
- **Home** "Why this today" link is now left-justified in the coach card (Spacer moved
  between the two links).

## Tests
- `CadenceCore swift test`: **403 pass / 0 failures** (+7: `SessionRosterTests`-style
  roster, no-clobber `updateSet`, performer reassign, `changeExercise` in
  `StrengthEditingTests`).
- New `CadenceUITests/StrengthEditingUITests`: **9/9 pass** (one per reported item).
- iOS `xcodebuild build`: BUILD SUCCEEDED.
- New seeds: generic `person.<name>`, `historyPartnerSession`.

## Notes
- Existing partner UI tests (`FR1PartnersUnitsUITests`, `FR10Feedback3UITests`) were
  already stale (legacy `set.weight`/`set.performedBy` keypad ids + missing
  `person.Sam` seed) — not addressed here; the new suite uses current `inline.*` ids.
- Simulator was degraded ("no debugger version", ~20–80s launches); tests verified
  green after a CoreSimulator restart.
