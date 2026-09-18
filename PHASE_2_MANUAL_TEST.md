# Phase 2 Manual Test

Use the current TestFlight build on real hardware. Do not use a simulator for
this close-out.

## 1. Prepare

You need:

- A real iPhone with the current build.
- A paired Apple Watch with Cladiron installed.
- The same Apple ID/iCloud account on both devices.
- A second iPhone on the same Apple ID for the private-iCloud convergence test.
- Bluetooth/Wi-Fi enabled and Health/Workout permissions granted.

On iPhone, open Settings → iCloud Details & Diagnostics and confirm the
account is available. Use Sync to Watch Now only when you want an explicit
Watch payload refresh. Do not use legacy backup recovery; normal iCloud sync
is automatic.

## 2. Workout Plan → Watch → iPhone

1. Open Home → Start Workout → Suggest a Workout.
2. Confirm one Personalized Workout opens directly in Workout Plan edit mode;
   there is no View Suggested Workout chooser.
3. Verify the plan contains exercises appropriate to the selected style and
   does not show Olympic-only movements in Fitness or Bodyweight suggestions.
4. Edit one exercise and its reps/loads. Use an exact ladder such as 12-10-8,
   including a fractional load if appropriate.
5. Confirm Start Workout and Schedule this Workout are equal-sized actions.
6. Start the plan on the iPhone, then use the paired Watch to log at least one
   planned set and finish the session.
7. Reopen Cladiron on the iPhone and confirm the workout appears once with the
   selected exercise identity, reps, loads, history, and volume intact.
8. Repeat with a Custom Workout: add an exercise, verify its plan volume, and
   confirm the Watch/iPhone execution path does not substitute an older exercise.

## 3. Schedule and resume a reviewed workout

1. From either Personalized Workout or Custom Workout Plan, tap Schedule this
   Workout and choose today or a future date.
2. Save. Confirm the plan closes to Home and Planned Workouts appears below
   Workouts Today.
3. Open Show more… and confirm today/future entries are listed. Create two
   entries on the same day and confirm both remain distinct.
4. Start one scheduled entry. Confirm the Workout Plan contains the exact
   saved exercise list, notes, reps, fractional loads, partner prescriptions,
   and warm-up/cool-down settings.
5. Abandon and resume it. Confirm it remains recoverable; complete it and
   confirm it leaves Planned Workouts and appears in history.
6. Reschedule another entry to a future date, then delete it. Confirm deletion
   removes it from active lists without resurrecting it after relaunch.

## 4. Same-user private iCloud convergence

On iPhone A:

1. Create a uniquely named Custom Workout and schedule it.
2. Optionally complete one short workout from it.

On iPhone B, signed into the same Apple ID:

3. Wait for the scheduled workout and history to appear without export/import.
4. Confirm title, exercise identity, sets, reps, loads, schedule date, and
   completion state match.
5. Edit a different workout field on B and wait for the change to return to A.
6. Relaunch both apps and confirm there are no duplicates, stale substitutions,
   missing sets, or lost tombstones.

## 5. Record the result

Record device models, OS/watchOS versions, build number, timestamps, and
screenshots of the Workout Plan, Watch execution, Home Planned Workouts, and
reconciled history. Phase 2 closes when the Watch execution/reconciliation and
same-user private-iCloud tests both pass.
