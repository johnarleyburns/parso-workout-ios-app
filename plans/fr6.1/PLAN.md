# FR-6.1 — One-time Gmail-draft importer

> One-time importer that parses the existing Gmail-draft format (category,
> exercise, weight, sets×reps, PR, last-time) into the local store.

## Design
- `GmailImporter.parse` (pure, well-tested) turns pasted text into
  `ParsedSession`s + flagged `ParseIssue`s. `WorkoutRepository.apply` writes them
  to the store, creating exercises as needed and recomputing PRs from data
  (markers are parsed-and-ignored).

## Mockups
Settings → Import: a paste area (with a "Load sample" helper), Parse → a preview
of parsed sessions + a flagged-lines count → "Import N sessions" (UC-7).

## Implementation
1. `ImportView`: `TextEditor`, parse, preview list, issues, confirm → `apply`.
- a11y ids: `import.text`, `import.sample`, `import.parse`, `import.preview`,
  `import.issues`, `import.confirm`, `import.done`.

## Automated testing
- **Unit:** `GmailImporter` grammar (8 cases). `apply` writes sessions. (Done.)
- **UI:** Settings → Import → load sample → Parse → preview shows → Import →
  success; the session appears under Train.
