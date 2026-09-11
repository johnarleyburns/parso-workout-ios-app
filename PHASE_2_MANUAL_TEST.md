# Phase 2 Manual Test

Use the current TestFlight build on real hardware. Do not use a simulator.

## 1. Prepare

You need:

- A real iPhone with the current TestFlight build.
- A paired Apple Watch with Cladiron installed.
- The same Apple ID/iCloud account on both devices.
- For the full iCloud test, a second iPhone running the same build and signed
  into the same Apple ID.
- Bluetooth and Wi-Fi enabled.
- Health and Workout permissions granted.

On iPhone:

1. Open Cladiron → Settings.
2. Confirm **iCloud Sync: Available**.
3. Open the Apple Watch settings and tap **Sync to Watch Now**.
4. Open **iCloud Details & Diagnostics** and confirm the account is available.

Do not use **Attempt Legacy Backup Recovery**. Normal sync is automatic;
**Refresh Status** only checks status and does not force a sync.

## 2. Test authored plan → Watch → iPhone reconciliation

1. Open **Plan → Routines → New blank week**.
2. Select today’s weekday.
3. Tap **Add session**.
4. Rename it to something unique, such as `P2 Field Test 2026-09-10`.
5. Tap the session and choose **Add strength**.
6. Choose a distinctive exercise, preferably one that previously showed the
   wrong substitute.
7. Configure three working sets:
   - Set 1: 12 reps
   - Set 2: 10 reps
   - Set 3: 8 reps
8. Save the strength item, finish the session, and save the plan.
9. Reopen the plan and verify that the exercise name and `12-10-8`
   prescription persisted correctly.
10. Tap **Sync to Watch Now** from Settings.
11. On the Watch, open Cladiron → **Your Plan**.
12. Confirm the planned session shows:
    - The exact session title.
    - The exact selected exercise.
    - The correct rep ladder.
    - No old substitute or stale exercise name.
13. Start the session from the Watch.
14. Lock the iPhone or leave it aside while exercising.
15. Log the planned sets on the Watch.
16. Tap **Finish & Save**.
17. Reopen Cladiron on the iPhone.
18. Confirm the completed workout appears with:
    - The same exercise identity.
    - The performed reps and loads.
    - No duplicate workout.
    - No stale substitute.
    - Correct history and progress updates.

If available, repeat the flow with a planned cardio session and verify its
duration, activity, and target zone on the Watch.

## 3. Test same-user private iCloud convergence

Use two iPhones, both signed into the same Apple ID.

On iPhone A:

1. Create a uniquely named plan, such as `iCloud P2 A`.
2. Save it.
3. Optionally complete one short workout from it.

On iPhone B:

4. Open Cladiron and wait for the plan to appear.
5. Confirm that the plan title, session, exercise, sets, and rep prescription
   match.
6. Edit the plan on B—for example, rename it to `iCloud P2 B` or add a
   session.
7. Save the change.
8. Wait several minutes, then reopen Cladiron on A.
9. Confirm that the edit appears on A.
10. Complete a short workout on B.
11. Reopen Cladiron on A and confirm that the workout history appears without
    duplicates or missing sets.

The test passes when both devices converge on the same plan and workout state
without manual export/import, data loss, duplicate records, or stale exercise
identities.

## 4. Record the result

Capture:

- iPhone and Watch models.
- iOS and watchOS versions.
- App version/build.
- Approximate timestamps.
- Screenshots of the Watch plan, completed Watch session, and reconciled iPhone
  history.
- Any stale exercise, incorrect reps, missing workout, duplicate, or sync
  delay.

Phase 2 is complete when both the Watch reconciliation path and the two-iPhone
same-user iCloud convergence path pass.
