# W3 — Strength flow parity (rename, lifecycle, warm-up/cool-down, save/cancel)

Fixes user report **4**: "lifts when entered i have no way to save or exit
normally/cancel like a normal workout, i expect it to say **strength** not lifts
and follow the normal on-iphone flow of warmup, one or more lifts, cooldown, at
any time save or cancel."

## What the code does today (`WatchStrengthView.swift`)

- Title/labels say **"Lift"** ("Start Lift" in launcher, `.navigationTitle("Lift")`).
- `.onAppear { startSession() }` creates a `WorkoutSession` **immediately** —
  swiping back from the picker leaves an orphan session in the watch store (and
  the HK session running until `stopWorkout` in… nothing; it leaks).
- The only exit is a "Done" toolbar button **visible only on the picker step**;
  from Log Set or Rest there is no way out except logging more sets.
- No Cancel/discard at all; `finishWorkout()` always syncs whatever exists.
- No warm-up or cool-down concepts (phone has per-set `isWarmup` + a cool-down
  timer writing `session.cooldownSeconds`).
- Step machine is `pickExercise → logSet → rest → logSet…` with no back edges.

## Phone flow to mirror (SessionView.swift, 1660 LOC — the reference semantics)

- Warm-up = **per-set flag** (`SetEntry.isWarmup`), toggleable, excluded from PRs
  and "previous set" hints (`Models.swift:405,416`).
- Cool-down = **timer** at session end writing `session.cooldownSeconds`
  (`SessionView.swift:552-557`), duration defaulted from `settings.cooldownMinutes`.
- Finish → summary; Cancel is confirm-guarded; an empty session is discarded
  silently (`SessionView.swift:1391`).

The watch mirrors these *semantics* (same model fields, same repository calls) —
not the phone's screen layout.

## Design

### Naming
"Strength" everywhere: launcher row **Strength**, nav titles, summary. No user-
visible "Lift". (Internal type names keep `Strength`/existing names; no renames
of code symbols beyond the view's own strings.)

### Lifecycle state machine — `WatchStrengthFlowModel` (new, CadenceFeatures, pure)

```
idle ── Start ──▶ active(warmup) ──▶ active(lifting) ──▶ cooldown ──▶ summary
                     │                    │                  │
                     └──── Cancel (confirm) ─────────────────┘──▶ discarded
                     └──── Finish & Save (anywhere) ────────────▶ cooldown? → summary
```

- **Session is created lazily** — only when the first set is logged (or first
  exercise added). Backing out before that = nothing persisted, HK session
  discarded (`stopWorkout(save: false)` from W1).
- **Warm-up**: the keypad gets a **Warm-up toggle** (flame icon, same semantics
  as phone `isWarmup`); the session-home shows warm-up sets with the phone's
  flame badge. Optional "start with warm-up sets" is just the toggle defaulting
  ON for the first sets of the first exercise (decision D3).
- **Cool-down**: after Finish, an optional cool-down timer screen (default
  `settings.cooldownMinutes`, +1m / skip), writing `session.cooldownSeconds` —
  same field the phone writes. Skippable in one tap.
- **Save / Cancel anywhere**: session home always shows **Finish & Save** (green)
  and **Cancel** (red, confirm dialog: "Discard workout? / Keep going"). Log Set
  and Rest screens get a top-left back chevron to session home (so the exit is
  always ≤2 taps away). Cancel:
  - not-yet-synced session → delete locally, discard HK session, done;
  - sets already synced (transferUserInfo is fire-and-forget) → also enqueue
    `{"action": "discard_session", "session_id": …}`; phone deletes by UUID
    idempotently (no-op if never received the sets).
- **Summary**: exercises × sets, total volume (in preferred unit, W2), duration,
  avg HR; Save writes the `HKWorkout` (W1 teardown) + `end_session` sync as today.

### Screens (see `watch-mockups.html` §Strength)
1. **Session home** — exercise list w/ set counts, Add Exercise, Finish & Save,
   Cancel. This replaces the current "picker" as the hub.
2. **Add exercise** — recents first (from watch store), then common list; keeps
   dictation via the system keyboard affordance.
3. **Log set** — weight (unit-aware, W2), reps, Warm-up toggle, Log Set; back
   chevron to home.
4. **Rest** — unchanged mechanics (`RestTimerModel`), plus "End rest" back edge
   and visible next-exercise context.
5. **Cool-down** — timer with skip.
6. **Summary** — stats + Done.
7. **Cancel confirm** — dialog.

## Data-model deltas
- None. (`isWarmup`, `cooldownSeconds`, `endedAt` all exist; discard action is a
  WC payload, not schema.)
- New WC userInfo action: `discard_session` (additive; phone ignores unknown
  actions today — `AppModel.swift:192` default branch — so old phones are safe).

## Implementation steps
1. `WatchStrengthFlowModel` in CadenceFeatures: states, transitions, lazy-create
   rule, cancel semantics, summary aggregation (volume via `effectiveLoadKg`,
   owner sets only). Headless tests are the bulk of this phase.
2. Split `WatchStrengthView` (314 LOC, near the 400 budget) into
   `WatchStrengthHomeView` / `WatchSetKeypadView` / `WatchRestView` /
   `WatchStrengthSummaryView`, each a thin render of the flow model.
3. Phone: handle `discard_session` in `AppModel` (delete-by-UUID via repository).
4. Launcher: "Start Lift" → **Strength**, icon unchanged (`dumbbell.fill`).
5. Wire cool-down timer (reuse `RestTimerModel` with cooldown default).

## Testing
- `swift test`: full transition table incl. cancel-before-create (no session
  persisted), cancel-after-sync (emits discard payload), finish-with-zero-sets
  (auto-discard like phone `:1391`), warm-up sets excluded from volume/previous.
- Watch smoke: unchanged cap; the existing start→stop smoke now exercises
  Finish & Save.
- Device: full workout with warm-up sets + cool-down; confirm it appears on the
  phone merged correctly; cancel a workout and confirm nothing appears.

## Open questions
→ `decisions.md` D3 (warm-up default), D4 (partner sets on watch — v2 Phase 4
was never built; is it still wanted, or does watch-only mean solo?).
