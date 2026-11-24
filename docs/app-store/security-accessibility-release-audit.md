# Security, Accessibility, and App Store Release Audit

Audit date: 2026-09-24

## Corrected in the app

- Added privacy manifests to the Watch app and widget extension. Each bundle
  declares no tracking and its UserDefaults required-reason API use.
- Removed the unused iPhone Motion usage description. The app does not import
  Core Motion or request motion authorization.
- Added a 256 MiB encoded-import limit and a matching 256 MiB gzip inflation
  limit. The limit applies before decoding, to file imports, and to the legacy
  CloudKit recovery asset path.
- Preserved accessible labels on the high-frequency icon-only workout controls
  (minimize/close/delete/rename/save-to-Health, partner management, and volume
  warnings).
- Added `scripts/check-release-safety.sh` to the local guardrails and CI. It
  validates shipped plist/privacy-manifest files, required purpose strings,
  export-compliance metadata, absence of the unused Motion permission, and
  tracked credential-like files.
- Disabled CloudKit mirroring for the submission build and removed the iCloud
  entitlement so HealthKit-derived workout data is never written to iCloud
  (Guideline 5.1.3(ii)). Settings, Transparency, and About now describe
  on-device storage and export/import.
- Added the iPhone FileTimestamp (C617.1) and DiskSpace (E174.1) required-reason
  declarations plus the Watch SystemBootTime (35F9.1) declaration.
- Added `NSLocationAlwaysAndWhenInUseUsageDescription` and request Always only
  when an outdoor workout starts; removed the unused `remote-notification`
  background mode.

## Manual release gates

- Run the real-device HealthKit, Bluetooth HR, GPS, Watch, StoreKit,
  export/import, and accessibility field tests in the release checklist.
  Generic builds cannot prove hardware authorization or sensor behavior.
- Capture final iPhone and Watch screenshots without debug seed data and verify
  the App Store Connect age rating, privacy answers, support URL, privacy URL,
  and contribution metadata.

## Resolved — App Review 5.1.3(ii) health-data policy

The shipping app previously mirrored its rich workout model, including
fitness/health measurements, through the user's private CloudKit database. App
Review Guideline 5.1.3(ii) prohibits storing personal health information in
iCloud.

**Resolution for the App Store submission:** the phone opens one local-only
`Cladiron.store` (`cloudKitEnabled: false`), the iCloud entitlement is removed,
and all iCloud/CloudKit settings copy and diagnostics links are gone. The Watch
continues to sync to the phone over WatchConnectivity. JSON export/import is the
portable backup path.

Before public submission, delete the legacy CloudKit container
`iCloud.guru.parso.cladiron.sync` (or its health-bearing record types) so data
mirrored by earlier builds is removed from iCloud. Re-enabling cross-device
sync requires a health-data-separated design first; do not simply turn the
single-store mirror back on.
