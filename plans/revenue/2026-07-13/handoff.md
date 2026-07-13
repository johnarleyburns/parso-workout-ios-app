# Agentic handoff

Paste the block below to launch a coding agent on this plan.

---

You are implementing the Cladiron revenue plan at `plans/revenue/2026-07-13/`.

Read, in this order:
1. `CLAUDE.md` — especially the **HARD RULE** (every coaching output must cite
   navigable science) and the convention that logic lives in `CadenceCore` /
   `CadenceFeatures`, **never in a `View`**.
2. `plans/revenue/2026-07-13/00-overview.md` — the phase table and testing posture.
3. `plans/revenue/2026-07-13/decisions.md` — **locked decisions D1–D8. Do not
   re-litigate them.**
4. The phase file you are executing.

Background, if you want the "why": `docs/COMPETITIVE-ANALYSIS.md`.

## How to work

Work **phase by phase, in order, 0 → 6**. For each phase:

1. Branch off `main`: `git checkout -b phase-N-<slug>`.
2. Implement exactly the steps in that phase file. **Do not scope-creep into later
   phases.**
3. Write the tests listed under that phase. **`swift test` only — do not add
   XCUITests.** `scripts/check-test-pyramid.sh` caps the UI suite at 12 and will fail
   CI if you exceed it.
4. Verify:
   ```sh
   cd CadenceCore && swift test
   xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build
   scripts/check-test-pyramid.sh
   scripts/check-no-network.sh    # from Phase 3 onward
   ```
5. Update `current_state.md` with what shipped and the new test count.
6. Commit with the message given in the phase file, ending with the `Co-Authored-By`
   trailer. Merge to `main` (`git checkout main && git merge --ff-only <branch>`),
   push, and confirm CI is green **before starting the next phase**.

## Non-negotiables

- **D4 (Phase 4).** Passive readiness **fuses with** self-report and never replaces
  it. The coach already cites `sawMonitoring2016` — *"self-reported measures trump
  objective monitoring."* Shipping a coach claim that contradicts a citation the coach
  already carries violates the HARD RULE. Self-report wins wherever present; passive
  signals fill the gap and *prompt* the check-in. Read `decisions.md` §D4 in full.

- **Every new coaching output cites science.** Resolve IDs via
  `CitationRegistry.citation(forId:)`, render with `CitationLink`, never display a raw
  ID. `CitationRegistry.all` and `docs/CITATIONS.md` must stay in sync (CI-enforced).

- **Logic goes in `CadenceFeatures`/`CadenceCore`, not in a `View`.** If a fix is
  tempting to make inside a `View`, that is the signal it belongs one layer down.
  Phase 2 exists precisely because a business rule was written at a SwiftUI call site,
  where no test could reach it — and it shipped an advertisement to paying customers.

- **Schema changes are additive only** — optional or defaulted. No destructive
  migration; older JSON exports must keep importing.

## Stop and ask — do not guess

- The Phase 3 image pipeline output exceeds ~50 MB.
- Any phase appears to require a destructive schema migration.
- A new coaching claim has no citation you can source. **Do not invent one, and do not
  ship the claim uncited.**

## Report at the end of each phase

- The commit SHA.
- `swift test` count, before → after. (Baseline: **945**.)
- CI status.
