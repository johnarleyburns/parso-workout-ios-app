# Phase 3 — Reliably sync completed watch cardio to iPhone

## Reported behavior

A cardio workout completed on Apple Watch never appeared on iPhone despite
multiple sync attempts.

## Implementation

- Audit `WatchCardioSessionView`, `WatchCardioSummaryView`,
  `WatchWorkoutManagerSync`, iPhone `AppModel` WCSession delegates, and
  `HealthKitProvider` ingestion. Identify whether completion is never enqueued,
  decoded but dropped, or duplicated/hidden by source matching.
- Define one Codable, versioned completion envelope containing a stable workout
  UUID, type/title, start/end, HR samples/summary when collected, route/distance
  only when GPS was enabled, and source `.watch`.
- Enqueue completion with durable `transferUserInfo`; retain it until the phone
  sends an acknowledgement for the workout UUID. Retry pending completions on
  activation/reachability/manual sync without creating duplicate workouts.
- On iPhone, decode on every WCSession delivery path, ingest transactionally,
  deduplicate by stable UUID, refresh Home/History, and acknowledge both new and
  already-ingested records. Reconcile HealthKit imports against the same workout
  where possible rather than inserting a second record.
- Surface pending/last-success/error sync state on the watch summary or sync
  action so repeated taps are meaningful.

## Tests and acceptance

- Unit-test codec/version handling, offline queue/retry/ack, duplicate delivery,
  app-relaunch pending state, malformed payload, and HealthKit reconciliation.
- Extend watch smoke with a test-mode transport seam and assert one phone-side
  record after repeated delivery. Keep hardware verification explicit.
- Acceptance: a watch-completed cardio appears once on iPhone after connectivity
  resumes, including when either app was backgrounded or relaunched.

