# Phase 4 Manual Test

This checklist covers the individual-user platform-polish slice. It is a real
device review checklist; no simulator result substitutes for HealthKit,
WatchConnectivity, Handoff, or iCloud behavior.

## 1. Bounded planning request

1. Open **Plan** → **Describe a plan**.
2. Enter: `4 days, 60 minutes, hypertrophy, intermediate, dumbbells and cable,
   8 week block, double progression, deload, avoid barbell back squat`.
3. Confirm the review lists the parsed goal, experience, days, duration,
   equipment, horizon, progression, periodization, and avoidance constraint.
4. Tap **Review in planner**. Confirm a normal editable plan opens and that the
   request is metadata/context for authoring; it does not silently generate
   exercises or prescriptions.
5. Close and reopen the authored plan. Confirm its title, block shape, and
   authoring context remain intact.
6. Try a retired request containing `trainer`, `client`, `Pro`, `trial`, or
   `share`. Confirm the UI explains that this is not supported and offers no
   sharing or paywall path.

## 2. Readiness

1. On **Today**, tap **How are you feeling?**.
2. Save a normal 1–5 check-in and confirm the Home card summarizes it.
3. Reopen it, change values, and save. Confirm it updates rather than creates
   duplicate entries for today.
4. Select **Pain or illness concern**. Confirm the safety copy is neutral and
   the coach presents a lighter/safety cue without forcing a medical decision.
5. Leave readiness empty on a fresh day. Confirm planning and execution still
   work; readiness is optional.

## 3. Widget, Shortcuts, and Handoff

1. Build/install on a physical iPhone with the `group.guru.parso.ios-workout-app`
   application group registered for both app IDs.
2. Open Today once, then add the **Today's workout** widget. Confirm it shows
   the current coach plan, today's session labels, and readiness when present.
3. Run **Start Today's Workout** and **Show Today's Plan** from Shortcuts/Siri.
   Confirm the first opens the workout picker and the second opens Plan.
4. Open an authored plan, move to the paired supported Apple surface, and
   confirm the Handoff activity returns to Plan. Confirm widget deep links open
   Plan as well.
5. With no network, confirm the widget, planner, readiness, execution, and
   history remain usable from local data.

## 4. Larger surface and accessibility

1. Review Plan on iPad/regular width. Confirm the list remains readable, rows
   remain tappable, and no planning data is hidden behind compact-only layout.
2. Test Dynamic Type at the largest accessibility size. Confirm no exercise,
   session, readiness, or action label truncates the essential value.
3. Navigate the Plan, Readiness, Home, and active-workout surfaces with
   VoiceOver. Confirm controls announce purpose, current values, and safety
   context; decorative icons are not announced as required actions.
4. Enable Reduce Motion and confirm planning, sheet presentation, and workout
   entry remain usable.

## Result

| Area | Pass / notes |
|---|---|
| Bounded planning review/apply | |
| Readiness save/update/safety | |
| Widget refresh/deep link | |
| Shortcuts/Siri | |
| Handoff | |
| Offline behavior | |
| iPad/regular width | |
| Dynamic Type/VoiceOver/Reduce Motion | |
