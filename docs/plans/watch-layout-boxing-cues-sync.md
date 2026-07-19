# Watch Layout, Boxing Cues, and Watch Sync Feedback

## Summary
- Rework Watch workout screens to fit normal flows on-screen without scrolling, especially interval setup and active interval controls.
- Update Watch boxing setup so warmup, round length, rest, cooldown, and rounds are visible and adjustable before start.
- Make Watch cues harder to miss: 3 haptics for phase start/end, 1 haptic at 30 seconds, and matching boxing bell audio when Watch workout sounds are enabled.
- Add visible phone/watch sync state on both devices: transient iPhone toast, Settings last-sync row, force sync, and Watch-side sync status/last sync/force sync.

## Key Changes
- Extend `IntervalSetupModel` with `warmupSeconds` and `cooldownSeconds`.
  - Boxing defaults: `rounds = 8`, `workSeconds = 300`, `restSeconds = 60`.
  - Warmup/cooldown default from app settings where available, falling back to current defaults: warmup 3 minutes, cooldown 2 minutes unless existing synced settings provide better values.
  - Clamp ranges: rounds `1...30`; warmup/work/rest/cooldown `0...600` where `0` is allowed only for warmup/cooldown, and `5...600` for work/rest.
- Redesign `WatchIntervalSetupView` as a compact non-scrolling-first screen.
  - Rows: Warmup, Rounds, Round, Rest, Cooldown.
  - Use inline `-` / `+` icon buttons plus compact monospaced values.
  - Step: 1 minute for warmup, round, cooldown; 30 seconds for rest; 1 for rounds.
  - Keep Start visible without needing scroll on common 41/45/49mm watch sizes.
- Redesign `WatchIntervalView` for tighter vertical fit.
  - Avoid top/bottom overflow by removing unnecessary `Spacer()` pressure, reducing timer scale dynamically with fixed min/max, using compact labels, and putting controls in a fixed-height bottom toolbar.
  - Controls remain tappable: pause/resume, skip, +1m, end.
  - Use simulator screenshots as visual verification for small and large Watch sizes.
- Add Watch audio cues.
  - Add `opening-closing-bell.mp3` and `warning-bell.mp3` to the Watch app target.
  - Add a watchOS cue player equivalent for boxing bells, gated by synced `workoutSounds`.
  - Phase transitions use opening/closing bell; 30-second warning uses warning bell.
- Update Watch haptics.
  - Start/end/phase transition cue: play 3 haptics in a short sequence.
  - 30-second warning: play 1 haptic.
  - Keep cue timing driven by existing `IntervalCueDecider`.
- Expand Watch sync state.
  - Add shared `WatchSync.Status`/payload helpers in `CadenceFeatures` for last sync date, in-progress state, success/failure text, and context dictionary keys.
  - Phone `AppModel.pushSettingsContext(force:)` tracks `watchSyncState`, `lastWatchSyncAt`, and `lastWatchSyncError`.
  - On successful `updateApplicationContext`, set last sync date and show toast status.
  - Add force sync in iPhone Settings and show last synced to Watch.
  - Add transient iPhone toast for `Syncing to Watch`, `Watch synced`, and failure.
  - Watch records `lastPhoneSyncAt` when application context arrives, shows a compact syncing/synced indicator in Settings, and sends a `request_settings_sync` message for force sync.
  - Phone handles `request_settings_sync` by pushing current settings context.

## Public Interfaces / Types
- `IntervalSetupModel`
  - Add `warmupSeconds: Int`, `cooldownSeconds: Int`.
  - Add initializer defaults or setup method that accepts synced/app warmup and cooldown seconds.
  - `intervalPlan()` uses user-selected warmup and cooldown instead of hardcoded values.
- `WatchSync.Preferences`
  - Add `warmupMinutes` and `workoutSounds`.
  - Preserve existing keys for unit, color-blind mode, rest seconds, cooldown minutes, and partners.
- `AppModel`
  - Add read-only sync state fields: `watchSyncState`, `lastWatchSyncAt`, `lastWatchSyncError`.
  - Update `pushSettingsContext(force:)` to be the single path for automatic and manual sync.

## Test Plan
- Core/unit tests only for automated acceptance.
  - Update `WatchCardioModelsTests` for boxing defaults: 5-minute work rounds, configurable warmup/cooldown, clamp behavior, and `intervalPlan()` warmup/cooldown output.
  - Add tests that warmup/cooldown allow zero but work/rest clamp to at least 5 seconds.
  - Extend `WatchSyncTests` for `warmupMinutes`, `workoutSounds`, context round trip, missing-key preservation, and invalid-value preservation.
  - Add a pure cue/haptic sequencing adapter test if implemented outside `WatchIntervalHaptics`, verifying transition maps to 3 events and warning maps to 1 event.
- Build checks:
  - `swift test --package-path CadenceCore`
  - `bash scripts/check-test-pyramid.sh`
  - `bash scripts/check-no-network.sh`
  - `xcodebuild build -project Cadence/Cadence.xcodeproj -scheme 'Cadence Watch App Watch App' -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO`
  - Package tests must use SwiftPM; the `CadenceCore` and `CadenceFeatures` Xcode product schemes are not configured for `xcodebuild test`. See `docs/TESTING.md`.
- Optional simulator visual verification:
  - Run Watch app in simulator with `-uiTestBoxingInterval`.
  - Capture screenshots for 41mm and 45/49mm watch sizes.
  - Verify setup controls and active interval controls are visible without initial scroll, text does not overlap the watch time/status area, and bottom controls are tappable.

## Assumptions
- Phone sync feedback will be toast-only outside Settings.
- Boxing setup uses 5-minute round default with 1-minute +/- step; rest uses 30-second +/- step for practical boxing timing.
- Watch workout sounds follow the existing iPhone `Workout sounds` setting via Watch sync.
- No simulator UI tests are required for automated acceptance; screenshots are manual/diagnostic layout verification only.
