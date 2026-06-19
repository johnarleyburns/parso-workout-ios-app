# 05 — Coach-driven Home (the primary path)

## Directive (user, 2026-06-15)
"Every time they start the app, the coach recommends what to do, and they can either
do that, or 'Start Workout' on their own, or log a workout they already did — a simple
Home-view path."

## The model
Home leads with **one Coach card** + **three primary actions**. Nothing else competes
for attention above the fold.

```
┌─────────────────────────────────────────────┐
│  COACH · Today                                │
│  “Lower body — Squat focus”                    │
│  4×5 @ ~102.5 kg · add 2 sets to hamstrings    │
│  ▸ Why / the science  (cited, expandable)      │
│  [ Do this workout ]   ← prescribed session    │
├─────────────────────────────────────────────┤
│  [ Start Workout ]   (choose your own)         │
│  [ Log a Workout ]   (something you did)       │
├─────────────────────────────────────────────┤
│  ▸ This week: volume, e1RM, body-part gaps     │
│  ▸ History · Assessments · Coach details       │
└─────────────────────────────────────────────┘
```

### The three paths (the whole spine)
1. **Do this** → opens the logger **pre-filled** with the engine's prescribed
   exercises + per-set targets (load/reps/RIR). The fast, default path.
2. **Start Workout** → the existing manual Start picker (strength / cardio incl.
   boxing / HIIT). User drives.
3. **Log a Workout** → the manual after-the-fact logging already shipped (PR #28).

### What the Coach card shows
- A concrete, **actionable session** for *today* (not a vague tip), derived from the
  engine (`03`): which muscles/lifts, sets, target load/reps/RIR, and *why* (volume vs
  MEV/MAV/MRV, e1RM trend, recovery, lagging parts).
- An optional **assessment prompt** when one is due (`04`): "Re-test bench 1RM today?"
- Always an expandable **"why + citation"** (D3).
- A graceful **cold-start** (new user, no history): the coach proposes a sensible
  starter session from the goal/experience intake, clearly labeled "starting point."

## How this reframes existing UI
- The batch-8 stat **tiles become secondary** (move below the three actions, as
  "this week" insights). Their quick-start taps still work but are no longer the hero.
- The current `HomeView` hero ("Start Workout") **demotes to action #2**; the Coach
  card is the new hero.
- "Log a Workout" stays as action #3 (already wired).

## Data / engine touchpoints
- Coach card calls `InferenceEngine.run(facts)` (`03`) → top `Recommendation` of kind
  `.session`, rendered with its prescription + citation.
- "Do this" materializes a `WorkoutSession` pre-loaded with the prescribed exercises
  (reuse `startSession`/`plannedExerciseNames`) and seeds per-set targets the logger
  reads (additive fields or an in-memory prescription handed to `SessionView`).
- Recompute on each appear (cheap, deterministic); cache last snapshot for instant paint.

## Phase
Lands in **P5** (prescriptive engine) for the real recommendation, but the **layout**
(Coach card placeholder + the three-action spine) can land in **P3** showing cited
*insights* first, then upgrade to a full prescription in P5. Onboarding/goal intake
(P7) feeds the cold-start.

## Testing
- UI: Home shows Coach card + the three actions; "Do this" opens a pre-filled logger;
  "Start Workout" and "Log a Workout" reach their existing flows; cold-start shows the
  starter recommendation.
- Engine integration: the card renders the top recommendation + a citation; never blank
  (cold-start fallback always present).

## Open
- Exact "Do this → logger" prefill mechanism (additive per-set target fields on the
  session vs a transient prescription object). Decide in P5.
- One recommendation vs a small ranked few on the card (recommend: one primary + a
  "more options" disclosure).
