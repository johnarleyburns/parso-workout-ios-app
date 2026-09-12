# Phase 3 manual field test

This is the human acceptance pass for the Phase 3 planning and supporter slice.
Run it on a TestFlight build with a real iPhone and paired Apple Watch. Use the
same Apple ID on both devices. Run the private-sync section with two supported
devices signed into that same Apple ID.

Do not use a second Apple ID, trainer/client sharing, Pro, trials, paywalls, or
legacy backup recovery. Those are retired non-goals.

## 1. Baseline and plan authoring

1. Install the candidate TestFlight build and confirm existing personal history
   is still present.
2. Open **Plan → Routines** and create or open a weekly plan.
3. Add at least one strength, cardio, mobility, and instruction item. Save the
   plan, leave the screen, and reopen it. Confirm all four item types persist.
4. Add or edit an exercise using the search field. Search once by canonical name,
   once by a muscle (for example `lats` or `chest`), and once by equipment.
   Confirm results arrive quickly and the selected muscle filter is reflected in
   the results.
5. Open exercise substitution from the plan. Choose a substitute, save, and
   confirm the new exercise is shown in the plan and in the workout preview.
   Confirm an older substitute cannot silently replace the newer plan choice.
6. Check several rep prescriptions. Confirm common descending ladders such as
   `12-10-8` and `12-10-8-6` remain distinct and that no malformed repeated
   ladder such as `12-12-12` is introduced by the planner.

## 2. Planning depth and coach review

1. From the plan, open **Plan depth**.
2. Create a four-week mesocycle with accumulation → intensification → deload.
   Confirm the phase labels, week count, progression intent, and deload week
   are visible before applying changes.
3. Repeat one session onto selected days. Repeat one week into the mesocycle.
   Confirm copied sessions have independent editing and execution state, and
   that a day never exceeds the supported two-session limit.
4. Open **Review with Coach**. Inspect rationale, citations, critique, insights,
   progress, autoregulation, and substitution sections.
5. Apply one explicit coach proposal and decline another. Confirm only the
   accepted proposal changes the saved plan. No coach action may silently mutate
   the plan.
6. Reopen the plan and review it after relaunch. Confirm the selected progression,
   periodization, substitution, and rationale remain attached to the plan.

## 3. iPhone → Watch → iPhone execution

1. Save or activate the authored/coach-reviewed plan on the iPhone.
2. Confirm the intended session is projected to the Watch with the exact exercise
   names, set count, reps, and any cardio/mobility instructions.
3. Start the session on the Watch. Log at least one strength set and one
   cardio/mobility item, then finish and save from the Watch.
4. Return to the iPhone and wait for reconciliation. Confirm the completed
   session appears once with the recorded values and no duplicate results.
5. Repeat once with the phone temporarily unavailable if practical. Confirm the
   Watch keeps the active execution state and reconciles after connectivity
   returns.

## 4. Optional supporter contribution

1. Open **Settings → Support Cladiron**.
2. Confirm the only contribution is the optional `$9.99 Contribute to
   development` product. There must be no Pro product, trial, paywall, or gated
   planning/execution action.
3. In the StoreKit/TestFlight environment, complete a purchase if you want to
   test it. Confirm the Home **Supporter** badge appears after a successful
   transaction and after relaunch. Test restore if offered.
4. Confirm all planning, coaching, export, partner execution, Watch execution,
   and sync workflows remain available without purchasing.

## 5. Same-user private iCloud convergence

1. On two devices signed into the same Apple ID and private iCloud database,
   create a small plan change on device A and wait for it on device B.
2. Edit a different field on device B and confirm it arrives on device A without
   losing either change.
3. Complete one session on one device and verify the result converges to the
   other device exactly once.
4. Relaunch both apps and repeat the checks. Confirm there is no cross-user
   sharing prompt, share zone, duplicate result, or silent data loss.

## Results

Record the build number, devices, watchOS/iOS versions, Apple ID/iCloud state,
and any failure with a screenshot and timestamp.

| Area | Pass / fail | Notes |
| --- | --- | --- |
| Plan item persistence |  |  |
| Muscle/equipment exercise search |  |  |
| Substitution correctness |  |  |
| Rep ladders |  |  |
| Plan depth / repeats |  |  |
| Coach review and explicit apply |  |  |
| Watch execution and reconciliation |  |  |
| Optional contribution / badge |  |  |
| Same-user iCloud convergence |  |  |

The known local limitation is the existing simulator UI smoke harness; this
field test is intentionally a real-device validation and does not require a
simulator run.
