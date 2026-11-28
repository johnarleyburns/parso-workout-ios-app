# Incident: 1184 lost strength history (November 2026)

## What happened

- **1.1.1183** ran with the iCloud entitlement and `cloudKitDatabase: .private(...)`
  for the single `Cladiron.store`. Watch-initiated strength sessions synced to the
  phone normally for months.
- **1.1.1184** removed the iCloud entitlement and opened the same store with
  `cloudKitDatabase: .none` in one step. The bootstrap treated the failed open as
  a corrupted store, quarantined `Local.store`/`Sync.store`/`default.store`, and
  started a new empty store. The user saw an empty app.
- **1.1.1185** merged every readable local store back: **59 strength workouts**,
  newest 11 Sep. Months of set-level data were not in any readable local store.
- The private CloudKit container was still intact but, in Production, had **no
  `CD_WorkoutSession` record type at all** — mirroring had never actually written
  workout rows there. The iCloud route could not recover anything.

## How the data was recovered

Two independent local sources still described the lost sessions:

1. **`HealthOutbox.json`** — the app's own durable queue of workouts waiting to be
   written to Apple Health. Each strength job carries the session id, dates, title
   and the **entire set list** in its metadata. Restoring it inserted 20 sessions
   with sets and replaced 44 duration-only summaries with set-carrying versions.
2. **`pre-single-store-native-db-v9.json`** — the 14.3 MB native snapshot the app
   writes before the split→single store migration. Merging it restored 679
   `SetEntry` rows and brought the live store to 163 strength sessions.

A one-time cleanup then hid the duration-only duplicates that the Health restore
had created (`EmptyDuplicateCleanup`).

## Root causes

1. **Sets in HealthKit metadata.** `strengthMetadata(for:)` encodes the whole set
   list into one `CladironOwnerSets` metadata field. A 20–30 set session is 3–5 KB,
   beyond what HealthKit accepts, so the Health copy of a strength workout is a
   summary with no set detail. Health was never a usable backup for volume.
2. **Destructive bootstrap on a configuration change.** A store that cannot be
   opened is treated as corrupt and replaced. A storage/entitlement change is not
   corruption and must not silently substitute an empty store.

## Follow-ups (not yet done)

- Cap or omit `CladironOwnerSets` so Health writes cannot exceed the metadata
  limit, and surface a health-save failure instead of retrying forever.
- Replace the quarantine-and-replace bootstrap with a blocking "your data is
  here — recover it" state when the failure is a configuration mismatch, and
  never auto-substitute an empty store for a populated one.
- Keep the JSON export as the documented, user-owned backup; it is the only copy
  that survived independent of the app.

## Verification after recovery

- 163 strength sessions, ~100 with full set detail, spanning June–November.
- 91 cardio workouts (never affected).
- The shipping build is local-only: no iCloud entitlement, no CloudKit code.
