# Phase 5 — Cancel Connect HR back to Home

## Reported behavior

The Connect Heart Rate screen has no clear way to abandon the workout and return
Home when HR will not connect.

## Implementation

- Add a visible Cancel action to `PreWorkoutHRView` with the stable
  `prehr.cancel` accessibility identifier. Thread an explicit `onCancel`
  closure from the Home launch route rather than relying on an ambiguous
  environment dismiss.
- Cancellation must stop a pending watch workout/relay, stop Bluetooth scanning,
  clear pending cardio launch/countdown state, dismiss setup surfaces, and leave
  no active workout. It must not save a cardio record.
- Route to the existing Home stack root. Preserve the separate “Continue without
  heart rate” action for users who still want to start.

## Tests and acceptance

- Headlessly test cancellation cleanup/idempotence and each launch route's state
  transition. Extend iPhone smoke to verify the Cancel control is available at
  the Connect HR gate.
- Acceptance: Cancel is always available and returns to Home cleanly, regardless
  of connecting, timed-out, connected, or permission-error state.

## Delivered

The grouped local commit `fadf1a9` adds Cancel, stops a pending watch request,
and clears the HR gate. Its full commit hook passed the unit, iPhone smoke, and
watch smoke gates. Hardware verification remains outstanding.
