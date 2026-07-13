# Phase 5 — Data durability

**Branch:** `phase-5-data-durability`
**Depends on:** nothing.
**Decision:** D5.

---

## Problem

Local-only storage plus a **manual** JSON export means the first user who loses or
replaces a phone writes:

> *"It deleted my entire training log."*

App Store rating is the dominant conversion factor on a product page, and early
reviews are permanent. **This is insurance, not growth** — it does not acquire a
single user, but it prevents the review that stops others converting.

## What the code says today — and it is good news

```
CadenceCore/Sources/CadenceCore/Models.swift:22
    //  • no @Attribute(.unique) — CloudKit does not support unique constraints
```

**The schema was deliberately kept CloudKit-compatible.** `current_state.md`
("Removed iCloud sync (now fully local)") shows sync was dropped for **positioning**
reasons, not technical ones. The model constraints never diverged, so re-adding is
low-risk.

---

## Design — ship the low-risk half (D5)

**Not** full SwiftData + CloudKit live sync. Instead: **automatic backup of the
existing `CadenceExport` v5 `.json.gz` blob to the user's private CloudKit
database**, with restore-on-fresh-install.

This:
- reuses `DataExport.swift` wholesale,
- leaves the SwiftData schema untouched (no migration risk),
- keeps the **Data Not Collected** label — the data lives in the *user's* iCloud,
  Apple is the processor, and you never see it,
- and solves the actual problem.

Live multi-device sync stays available later if demand appears.

---

## Steps

### 1. New `CadenceCore/Sources/CadenceCore/BackupPolicy.swift`

Pure, so all decision logic is testable with **no CloudKit in the test path**.

```swift
public struct RemoteBackupMeta: Sendable, Equatable {
    public let createdAt: Date
    public let sessionCount: Int
    public let schemaVersion: Int
}

public enum RestoreDecision: Sendable, Equatable {
    case none
    case offerRestore(RemoteBackupMeta)   // local data exists — ask first
    case autoRestore(RemoteBackupMeta)    // fresh install — safe to restore
}

public enum BackupPolicy {
    public static let minimumInterval: TimeInterval = 24 * 3600

    public static func shouldBackUp(lastBackupAt: Date?,
                                    lastLocalChangeAt: Date?,
                                    now: Date) -> Bool

    public static func restoreDecision(localSessionCount: Int,
                                       remote: RemoteBackupMeta?) -> RestoreDecision
}
```

### 2. New `Cadence/Cadence/Services/CloudBackupService.swift`

- `CKContainer.default().privateCloudDatabase`.
- A single `CKRecord` holding the `.json.gz` as a `CKAsset`.
- Encode and decode via the existing `CadenceExport` — do not invent a second
  serialization format.
- **Never blocks a workout.** Backup is opportunistic and off the critical path.

### 3. Entitlements

Re-add the iCloud container. **CloudKit without subscriptions does not need push** —
so `aps-environment` and the `remote-notification` background mode stay removed.
They were deliberately stripped; do not restore them.

### 4. Settings

An "iCloud Backup" toggle, a "Last backed up …" line, and "Restore from iCloud".
Default **on**, with one clear line of copy stating the data goes to *the user's own*
iCloud — **not to a Cladiron server**. This is a privacy-first app; the copy has to
say so plainly, because a user who sees "iCloud" and assumes "their server" is a user
who uninstalls.

### 5. Fresh install

- Local store empty + a remote backup exists → **`autoRestore`**.
- Local data present + remote is newer → **`offerRestore`**.

**Never silently overwrite user data.**

---

## Tests — `CadenceCoreTests/BackupPolicyTests.swift`

- due / not-due against `minimumInterval`; never backed up → due
- no local changes since the last backup → not due
- empty local + remote present → `.autoRestore`
- non-empty local + remote present → `.offerRestore` — **never silently clobber user
  data.** Name the test for this.
- no remote → `.none`
- an older-schema remote still decodes (v1–v4 exports already decode, per
  `DataExport.swift`)

All pure. No CloudKit in the test path.

---

## Acceptance

- `swift test` green.
- A fresh-install restore round-trips a full export **losslessly**: sessions, sets,
  cardio (including HR + GPS route samples), assessments, preferences, and the
  learned `CoachPreferenceProfile`.
- Privacy label unchanged (Data Not Collected).

## Commit

```
feat: automatic iCloud backup + restore of the export blob (private CloudKit, Data Not Collected)
```
