# FR-1.6 — Reusable session templates

> Reusable session templates (e.g., "Push Day").

## Design
- `SessionTemplate` + `TemplateExercise` models (name, ordered exercises with
  target sets/reps). `WorkoutRepository.createTemplate`, `allTemplates`,
  `deleteTemplate`, `startSession(from:)` which creates a titled session and
  pre-resolves the template's exercises into the library.

## Mockups
Train tab → "Templates" section listing saved templates, each a one-tap "Start".
A "New Template" editor adds named exercises with target sets×reps. Swipe to
delete.

## Implementation
1. `TemplatesView` (list + start + delete) and `TemplateEditorView`.
2. Train tab surfaces templates above the session list.
3. Starting a template creates a session titled after it (`templateName` set).
- a11y ids: `templates.new`, `template.start.<name>`, `templateEditor.name`,
  `templateEditor.addExercise`, `templateEditor.save`.

## Automated testing
- **Integration:** create template, start session from it resolves exercises &
  sets `templateName`. (Done.)
- **UI:** create a template with two exercises; start it; assert a new session
  titled after the template opens with those exercises available.
