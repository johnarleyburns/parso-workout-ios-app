# Phase 4 — Restore iPhone cardio connection to watch HR

## Reported behavior

Starting Other Cardio on iPhone and requesting watch HR never connects, even
with the watch app open; this previously worked.

## Implementation

- Trace iPhone `startWatchWorkout`, WCSession command transport, request IDs,
  watch command decoding/session start, rejection replies, and first HR sample.
  Log state transitions in debug builds with request ID and rejection reason.
- Activate WCSession before requests. Use immediate messaging when reachable and
  a durable command fallback when not; the watch must process both paths through
  one idempotent command handler and reply/ack with the same request ID.
- Repair stale `.alreadyActive`, stopped-session, timeout, and app-relaunch
  states. A retry must stop stale app-owned sessions, wait for teardown, and
  retry once without looping. Starting Other Cardio must use a supported
  HealthKit workout configuration.
- Ensure relay state is reset by cancel/end and that samples are accepted only
  for the active request. Do not let phase 3 completion traffic consume or mask
  HR command traffic.

## Tests and acceptance

- Unit-test reachable and queued command paths, ack/sample correlation, stale
  active-session recovery, timeout, duplicate commands, cancellation, and retry
  limit. Extend both existing smoke flows using transport seams.
- Hardware-test Other Cardio from a cold launch and after a prior workout ends.
- Acceptance: with permissions granted and watch app available, iPhone reaches a
  live zone/BPM state; failure presents a reason and leaves Continue/Cancel usable.

