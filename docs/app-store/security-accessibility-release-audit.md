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

## Manual release gates

- Run the real-device HealthKit, Bluetooth HR, GPS, Watch, iCloud convergence,
  StoreKit, export/import, and accessibility field tests in the release
  checklist. Generic builds cannot prove hardware authorization or sensor
  behavior.
- Capture final iPhone and Watch screenshots without debug seed data and verify
  the App Store Connect age rating, privacy answers, support URL, privacy URL,
  and contribution metadata.

## Policy decision required before public submission

The app currently mirrors its rich workout model, including fitness/health
measurements, through the user's private CloudKit database. Apple's current
App Review Guideline 5.1.3(ii) says apps must not store personal health
information in iCloud. Apple has not publicly clarified whether a private,
per-user CloudKit database or end-to-end encrypted fields are exempt. This is
therefore a submission risk that cannot be corrected by a plist or UI change.

Before public App Store submission, obtain an App Review consultation or choose
an architecture that keeps personal health information out of iCloud. Do not
represent the current private-CloudKit behavior as an App Store-approved
exception without that decision.
