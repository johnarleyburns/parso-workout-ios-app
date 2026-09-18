# Phase 4 Manual Test

Phase 4 is platform polish around the single-workout Home flow. The bounded
natural-language parser remains a tested core compatibility capability, but
its former Plan-tab review UI is intentionally retired with weekly planning.

## 1. Readiness and transparency

1. On Home, open How are you feeling? and save a normal 1–5 check-in.
2. Edit it and confirm today has one updated entry rather than a duplicate.
3. Select Pain or illness concern. Confirm the copy is neutral and the coach
   offers a lighter/safety cue without forcing a medical decision.
4. Open Settings → Transparency & Control. Confirm HealthKit ingestion, Coach
   refresh, Watch projection, iCloud mirroring, Supporter prompts, and retry/
   recovery controls explain what is happening.
5. Leave readiness empty on a new day and confirm workout creation/execution
   still works.

## 2. Widget, Shortcuts, and Handoff

1. Open Home once, then add the Today's workout widget. Confirm it uses the
   shared private snapshot and shows today's Planned Workouts and readiness when
   present; it must not claim a weekly coach plan.
2. Run Start Today's Workout from Shortcuts/Siri and confirm it opens the normal
   Start Workout picker.
3. Run Show Today's Plan and confirm it opens Planned Workouts, not a retired
   Plan tab.
4. Open a Workout Plan and move to the paired supported Apple surface. Confirm
   Handoff returns safely to Home/Planned Workouts. Confirm `cladiron://plan`
   deep links also land safely on Home.
5. With no network, confirm local workout creation, readiness, execution, and
   history remain usable.

## 3. Larger surface and accessibility

1. The focused iPad smoke checks only launch, absence of the Plan tab, Settings,
   and Transparency & Control. It intentionally does not duplicate the iPhone
   workout flow or test retired bounded-planning UI.
2. Review Home, Start Workout, Workout Plan, readiness, and Planned Workouts on
   a physical iPad/regular-width surface. Confirm rows remain readable/tappable.
3. Test the largest Dynamic Type size and confirm essential exercise, session,
   readiness, and action labels remain usable.
4. Navigate Home, Workout Plan, readiness, settings, and active workout with
   VoiceOver. Confirm controls announce purpose, values, and safety context.
5. Enable Reduce Motion and confirm sheets, scheduling, and workout entry remain
   usable.

## 4. Record results

Record build number, devices, OS versions, iCloud state, and failures with
screenshots and timestamps. Phase 4 is complete after the platform, accessibility,
offline, and performance review plus the final acceptance/Appendix AA proof.
