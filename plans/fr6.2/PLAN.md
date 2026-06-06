# FR-6.2 — Full data export & import (JSON/CSV)

> Full data export (JSON/CSV) and import — the user owns and can leave with their
> data.

## Design
- `WorkoutRepository.buildExport` → `CadenceExport`; `DataExport.encodeJSON` /
  `encodeCSV`. JSON re-import via `decodeJSON` + `WorkoutRepository.merge`
  (dedup by id). A `ShareLink` exports a file.

## Mockups
Settings → Export: format picker (JSON/CSV), a preview, a Share button, and a
"Restore from JSON" paste-import.

## Implementation
1. `ExportView`: format picker, generated preview, `ShareLink`, JSON paste import.
- a11y ids: `export.format`, `export.preview`, `export.share`,
  `export.importText`, `export.import`.

## Automated testing
- **Unit:** JSON round-trip, CSV format/escaping; `merge` dedup. (Done.)
- **UI:** seed history → Settings → Export → preview is non-empty; switch to CSV
  → preview updates (contains the CSV header).
