# FR-4.5 — Optional iCloud/CloudKit private-DB sync (off by default)

> Optional iCloud/CloudKit private-database sync across the user's own devices
> (off by default).

## Design
- `CadenceStore.makeModelContainer(cloudKitEnabled:)` selects
  `cloudKitDatabase: .private(...)` when enabled, else `.none` (fully local,
  FR-9.4). The toggle is `AppSettings.cloudSyncEnabled` (default false). Because
  the container is built at launch, enabling sync prompts a relaunch.

## Mockups
Settings → iCloud Sync toggle with a one-line explanation and "applies on next
launch" note.

## Implementation
1. Settings toggle bound to `settings.cloudSyncEnabled`.
2. App init reads the flag to choose the store configuration.
- a11y ids: `settings.cloudSync`.

## Automated testing
- **UI:** open Settings; toggle iCloud Sync on; assert the toggle reflects the
  new state (persisted in UserDefaults).
- **Integration:** `makeModelContainer(cloudKitEnabled:false)` builds a local
  store (covered implicitly by the repo suite running on in-memory stores).
