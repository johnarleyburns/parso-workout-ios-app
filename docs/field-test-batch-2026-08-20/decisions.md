# Decision sheet — field-test batch 2026-08-20

Every question below needs the user's answer **before implementation**. Once
answered, record verbatim here and do not re-litigate (repository rule).

## D1 — Rowing "optional GPS" treatment (P8)

**Recommended: Option A — treat Rowing like Cycle.** `WorkoutType.rowing.usesGPS = true`
routes it through the existing `startOutdoorWithGoal` → OutdoorCardioView flow.
"Optional" is satisfied by the optional distance-goal chooser, GPS needing
authorization (recorder tolerates no fixes), and the GPS-less Manual Log path.
Zero new routing code.

- **Option A** (recommended): Rowing = GPS box like Cycle; no new setup screen.
- **Option B**: new `RowingSetupSheet` with a GPS toggle, routing
  `.outdoor(.rowing)` or `.timer(.rowing)`.

## D2 — Alternation rule (P1)

**Recommended: strict even-spread.** `SetAlternation.spread` never emits two
consecutive rows from the same performer while at least two performers still
have outstanding rows (fair-queue order). This replaces the column round-robin
that the existing `testPendingSetsAlternateBetweenPerformers` enshrined with the
buggy `Me,P,Me,P,P` tail. Only when one performer alone has rows left does its
remainder emit consecutively (unavoidable and correct).

## D3 — `.alreadyActive` recovery (P5)

**Recommended: auto-stop + one retry.** On a watch rejection with
`.alreadyActive`, the phone sends `stop_workout`, waits ~1–1.5 s, then retries
`start_workout` exactly once with a fresh requestID. If the retry fails, surface
the error text. No loops.

## D4 — Live Activity scope (P5)

**Recommended: clean up stale activities, do NOT add the widget target in this
batch.** `endAllStale()` on launch + at the top of `start(title:)`. The widget
extension itself is the separately-planned
`plans/iphone-field-testing/2026-08-13/01-widget-extension-target.md` feature;
the user-reported "never stops" is primarily the **watch** session leak (5A),
fixed by the cardio stop-path wiring + recovery.

## D5 — Collapsed partner summary (P2)

**Recommended: replace, don't augment.** When partners are present, the
collapsed card shows per-partner "last time" segments (`Me: …; Sam: …`) and
drops the combined `6/6 sets`. No prior-session history for anyone → fall back
to the existing counts summary. The planned target sets remain visible in the
expanded card's pending rows.

## D6 — Big HR display surface (P7)

**Recommended: all three cardio live screens** — `RecordCardioView`,
`OutdoorCardioView`, **and** `IntervalView` (HIIT/boxing are cardio). The
strength live band stays as its compact band.

## D7 — Watch-side auto-tear-down defense (P5)

**Recommended: do not ship in this batch.** A watch-side watchdog that stops a
session after long phone-unreachability risks killing a legitimately-minimized
workout. Phone-driven stop + retry is the primary fix; revisit only if hardware
testing still leaks.

## D8 — Set-editor "no history" copy (P3)

**Recommended: explicit secondary text.** When the selected performer has no
prior-session sets, the history card shows "No previous history for <name>"
rather than absent text, so the "always show (if any)" requirement is visibly
satisfied and assertable in the smoke test.

## Execution protocol — NOT yet set

The previous two batches used different protocols (one-phase-stop vs
one-pass-push). This plan is written for review; **the user should state the
protocol before implementation** (e.g. "one phase, stop, wait" or "fix all,
commit and push"). Once stated, update `current_status.md` with it.
