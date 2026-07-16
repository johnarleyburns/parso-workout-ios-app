# Decisions — coach-user-control (2026-07-16)

Recorded verbatim from the planning session (do not re-litigate):

1. **Readiness:** *Notice it, stop nagging.* Count same-day HIIT/boxing as real intense
   load, drop redundant easy-cardio suggestions, surface "you already trained hard
   today" — but **never block or downgrade strength.** Assume HIIT/boxing are **always**
   intense regardless of HR; also fix the age/averaging bug so tracked-HR sessions
   classify correctly.
2. **Scheduling:** *User's scheduled days/week trumps coach recovery.* Never force a
   recovery day that drops a strength or cardio day the user asked for. The coach may
   **recommend** a lighter day when it sees several consecutive hard days, but athletes
   routinely train 6 hard days/week, so don't be trigger-happy. With **two-a-days on,
   plan strength AND cardio every non-rest day** and modulate intensity/mix rather than
   dropping days.
3. **Control UI:** *Contextual + two-a-day aware.* On a two-a-day the card lets the user
   pick a different strength **and** a different cardio; "Do a different cardio" and
   "Do strength anyway" appear where relevant.

Implementation decisions made during build (grounded in existing code):

- **maxHR formula:** reuse `CardioMath.defaultMaxHR(age:)` (Tanaka 208 − 0.7·age,
  fallback 190 ≈ age-30) rather than introducing a second 220−age formula — it is the
  formula the rest of the app (zones, YourWeekPresenter) already uses, and it is
  already cited (`tanakaMaxHR2001`).
- **Export fixture:** the real `Cladiron-Export-2026-07-14.json.gz` is git-ignored
  (personal health data, never committed). The regression tests reproduce its profile
  synthetically: age 50, 5 strength / 6 cardio / two-a-days / fixed Sunday rest, and
  the 7/06–7/13 HIIT/boxing sessions with their real avg/max HR values.
- **Completed-day navigation:** a day with >1 completed workout uses a chooser
  (confirmation dialog) listing each workout; single-workout days navigate directly.
- **Strength swap on a two-a-day:** the strength row's Start already lands on
  `WorkoutPlanEditor` (the setup surface) where exercises can be swapped; the added
  per-component control is the cardio "Different cardio" affordance + the
  "Do a different cardio" full-picker row in Alternatives.
