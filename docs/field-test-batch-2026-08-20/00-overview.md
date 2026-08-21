# Field-test batch — 2026-08-20 — Overview

Source: iPhone field-testing session reported 2026-08-20. **Eight** defects and
requests. This plan is written so an agent can execute it **without further
research or clarification**: every phase names the exact files, the exact
symbols, the exact acceptance criteria, the exact tests, and the exact commands.

> **Execution rule (for the user to set):** the previous batch ran as
> "commit and push in one pass". The batch before ran as "one phase, stop, wait
> for review". This plan is written **for review first** — do not start coding
> until the user approves the phases and answers the decision sheet
> (`decisions.md`).

---

## 1. Raw field-test issues → phase map

| # | Field-test issue (verbatim intent) | Phase |
|---|---|---|
| 1 | Planned partner workout: exercise order between partners is **unstable** ("sometimes the order changes inexplicably") and **not always alternating** ("sometimes I see the same name twice instead of interleaved") — it must be stable and alternate | **P1** |
| 2 | Active workout view: previous-workout weights/reps must show for **both partners** on the exercise **in collapsed form**, **NOT combined** — drop `6/6 sets`; render `Me: 185 lb x 5, 190 lb x 6; Sam: 125 lb x 20, 130 lb x 15` | **P2** |
| 3 | Set entry view: **always** show previous-workout weight/rep history (if any) **and** the previous current-exercise weight/reps (if not the first set) — **per selected partner**, and it must **update when the selected partner changes** | **P3** |
| 4 | Active workout view: vertical space between buttons is inconsistent — must use **HomeView spacing** | **P4** |
| 5 | Watch: a Cladiron "live activity"/timer **keeps running for hours** after a cardio workout and never stops; it **blocks reading HR from the watch** for future workouts; "Check for Live HR" leaves the iPhone HR screen unresponsive | **P5** |
| 6 | Cardio "Connect Heart Rate" view: **"Continue without heart rate" must stay clickable** even with an Apple Watch connection problem — it currently makes the screen inoperable | **P6** |
| 7 | Cardio with HR active: stop showing BPM/zone as small text with an average; show a **very large, bold, zone-colored HR number** (same zone colors as the Apple Watch) with zone + average in smaller text beneath | **P7** |
| 8 | Add **Rowing** as a cardio box **after Cycle**, optional GPS, rowing icon from the same sports set | **P8** |

## 2. Phase order and dependencies

```
P1 Stable alternating partner order     (CadenceFeatures only — no deps)
P2 Collapsed per-partner last-time      (depends: P1's SetDisplay/order work is independent; P2 standalone)
P3 Set-entry per-partner history        (depends: P2's formatter can be shared; P3 standalone otherwise)
P4 Session button spacing               (no deps — LayoutMetrics tokens)
P5 Watch session leak + Live Activity   (no deps)
P6 HR gate Continue always tappable     (depends: P5B `.alreadyActive` recovery improves it, but P6 is standalone)
P7 Big zone-colored HR display          (no deps)
P8 Rowing cardio box                    (no deps)
```

Do them in that order. Each is a self-contained commit (unless the user chooses
the "one pass" execution protocol).

## 3. Hard constraints that apply to EVERY phase

These are repository rules, not suggestions. Violating any fails the gate.

1. **Swift 6, strict concurrency, zero new warnings.** No `@unchecked`, no
   `nonisolated(unsafe)`, no warning suppression. Before pushing: clean-build the
   package **and** the app and pipe both through `scripts/check-owned-warnings.sh`
   (incremental builds do not re-emit warnings — the 2026-08-19 lesson).
2. **Logic lives in `CadenceFeatures` / `CadenceCore`, never in a `View`.**
   `CadenceFeatures` imports only Foundation, SwiftData and Observation. If an
   extraction wants a `Color` or a `View`, return a semantic enum and let the
   view map it. New CadenceFeatures files must stay under the 400-LOC budget.
3. **The XCUITest suite does not grow.** `SmokeLaunchTests.swift` keeps exactly
   **one** `func test…`. New assertions go *inside* that one test; everything
   else is `swift test`. `scripts/check-test-pyramid.sh` enforces this.
4. **Schema changes are additive only** (optional/defaulted, no destructive
   migration). None of these eight phases require a schema change.
5. **Every coach output cites science** — not implicated by any phase here
   (no new coach output is introduced).
6. **NFR-8: the coach suggests, it never proscribes; every surface keeps an
   escape hatch.** P6 is literally an escape-hatch fix. P3's "always show
   history" must never *block* saving a set.

## 4. Verification commands

- Core: `cd CadenceCore && swift build` / `swift test`
- App build: `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Commit gate: `make pre-commit` (guardrails, core tests, iPhone smoke) — budget
  ≥5 min; the hook outlives the agent's process budget, so run each stage
  individually and use the hook's `SKIP_LOCAL_GUARDS=1` escape hatch when
  necessary (2026-08-19 process note).
- Full regression: `make all-tests` (adds watch smoke + watch unit).
- Warning gate before any push: `scripts/check-owned-warnings.sh` against a
  **clean** build of both the package and the app.

## 5. Root-cause summary (so the phases read as a batch, not a pile)

- **P1**: two independent ordering bugs. `SessionRenderModel.interleaved`
  (`SessionRenderModel.swift:432-439`) is a column-major round-robin that emits
  consecutive same-performer rows whenever one performer is ≥2 rows ahead of the
  other — and the existing test `testPendingSetsAlternateBetweenPerformers`
  (`SessionRenderModelTests.swift:501-519`) actually **asserts** that buggy
  `Me,P,Me,P,P` tail. Separately, `SessionView.nextPerson()` (`SessionView.swift:
  939-949`) is a **session-global** rotation used by the editor prefill and
  `onRepeat`, decoupled from each exercise's pending alternation, so free-form
  adds can pick a different next person than the card's pending rows promise.
- **P2**: `SessionRenderModel.compactSummary` (`SessionRenderModel.swift:11-32`)
  combines both performers into `6/6 sets · reps · weight · PartnerName`; the
  per-performer "Last time:" lines only exist in the **expanded** card
  (`ExerciseCardView.swift:158-186`).
- **P3**: `InlineSetEditorView` shows only `contextText` ("Last set …", the last
  set logged *this session*, computed once in `SessionView.inlineEditorConfig`
  at `SessionView.swift:203-209`); it never shows prior-session history, and the
  text is computed per *config*, not per selected performer.
- **P4**: the active-workout surface mostly uses `LayoutMetrics`, but
  `ExerciseCardView.actionButtons` (`ExerciseCardView.swift:335-353`) pads its
  in-card buttons with the ad-hoc `.padding(.top, cardHeadingSpacing - 8)` (=2pt),
  breaking the card's rhythm versus Home's 20/16/12/10 tokens.
- **P5**: two leaks. (a) `model.stopWatchWorkout()` is called from only four
  places (strength end `SessionView.swift:872`, interval finish
  `IntervalView.swift:231`, HR gate `PreWorkoutHRView.swift:103/152`). Every
  **cardio** recorder end/cancel path never stops the watch, so the watch's
  `HKWorkoutSession` + `WKExtendedRuntimeSession` run for hours and the next
  `start_workout` is rejected `.alreadyActive`
  (`WatchWorkoutManagerSync.swift:65-67`), which is what blocks future watch HR.
  (b) The phone Live Activity coordinator
  (`WorkoutLiveActivity.swift:24-53`) only ends on `active.isActive` flipping
  (`RootTabView.swift:131-137`); a killed/backgrounded app orphans it and no
  launch-time cleanup exists.
- **P6**: `PreWorkoutHRView.swift:114` disables the Continue button while
  `watchSelected && watchBPM == nil && !strapConnected` — after tapping "Check
  for Live HR" with a flaky watch, the primary action is gone forever.
- **P7**: `RecordCardioView.swift:109-111` and `OutdoorCardioView.swift:94` show
  HR as a small grid metric; the watch already owns the zone color scheme
  (`WatchRootView.swift:331`, `WatchCardioView.swift:81-89`: Z1 cyan, Z2 green,
  Z3 yellow, Z4 orange, Z5 red).
- **P8**: `CardioType.rowing` already exists end-to-end
  (`Models.swift:893-927`, `figure.rower`, HealthKit `.rowing`, watch, calories).
  Missing: the `WorkoutType` entry taxonomy (`WorkoutType.swift:7-71`), the three
  picker arrays (`WorkoutTypePicker.swift:76`, `RecordCardioView.swift:29`,
  `CardioLogViews.swift:48`), `WorkoutHero.colors`
  (`WorkoutTypePicker.swift:276-287`), and
  `HealthKitProvider.distanceType(for:)` (`HealthKitProvider.swift:344-351`).
