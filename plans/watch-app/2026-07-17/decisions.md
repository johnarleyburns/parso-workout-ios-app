# Decision sheet — Watch App v3

Answered decisions get recorded verbatim here and are then settled (don't
re-litigate). All currently **OPEN** — answers needed before the noted phase.

## D1 — Live HR quick session (needed: W1)
Standalone "Live HR" only streams continuously inside a workout session. Plan
proposes: Start/Stop button running a **discarded** `.other` session (no rings
credit, nothing saved).
**Options:** (a) as planned — discard; (b) save it as an "Other" workout (gets
rings credit but pollutes history); (c) leave Live HR passive (only mirrors an
active workout; shows `--` otherwise, with explanatory copy).
**Recommendation:** (a).
**Answer:** _open_

## D2 — Which settings sync phone→watch in W2 (needed: W2)
Unit is required. Ride-alongs available cheaply: interval color-blind palette,
default rest seconds, cool-down minutes.
**Recommendation:** sync all four now (one context dict, same plumbing).
**Answer:** _open_

## D3 — Warm-up default on the watch (needed: W3)
Phone treats warm-up as a per-set flag. On the watch, should the keypad's
Warm-up toggle default **ON** for the first set(s) of the first exercise, or
always default OFF (matching the phone exactly)?
**Recommendation:** default OFF (phone parity; one tap when needed — least surprise).
**Answer:** _open_

## D4 — Partner sets on the watch (needed: W3 scope)
v2 Phase 4 (partners + smart swap on the wrist) was never built. Does
"watch-only" include partner training, or is the wrist solo-only for now
(partners stay a phone feature)?
**Recommendation:** solo-only in v3; revisit after W1–W4 ship.
**Answer:** _open_

## D5 — Swim lap counting (needed: W4)
Pool swims: HealthKit auto-counts lengths from `lapLength` and Water Lock
disables touch — so the "simple lap counter" is primarily *automatic*, displayed
big, with a **manual +1** on the controls page as fallback (usable when paused /
unlocked). Open water: no laps, distance instead.
**Options:** (a) as planned — auto with manual fallback, pool default 25 m (kg
users) / 25 yd (lb users); (b) purely manual counter (works everywhere, but
fights Water Lock mid-swim); (c) auto only, no manual.
**Recommendation:** (a).
**Answer:** _open_

## D6 — Rowing on the launcher (needed: W4)
`CardioType.rowing` already exists and `activityType(for:)` maps it. The user's
list didn't include it, but it's nearly free (indoor-only, same metrics as Other
+ distance).
**Recommendation:** include it, below Other, since the model already supports it.
**Answer:** _open_

## D7 — Auto-pause for outdoor run/walk (needed: W5 scoping only)
Apple Workout auto-pauses runs. Nice, but adds motion-detection complexity.
**Recommendation:** W5 backlog, not in W4.
**Answer:** _open_

## D8 — HIIT/Boxing plan customization on the wrist (needed: W4 scoping only)
Today the watch starts `hiitDefault()` / `boxingDefault()` with no setup screen
(v2 planned a protocol picker that wasn't shipped). Keep defaults-only in v3, or
add the compact rounds/work/rest setup?
**Recommendation:** defaults-only in v3 (not part of the reported feedback);
setup screen goes to W5.
**Answer:** _open_
