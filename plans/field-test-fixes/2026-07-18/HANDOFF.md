# Handoff prompt — field-test fixes 2026-07-18

Paste this to the implementing agent:

---

Implement `plans/field-test-fixes/2026-07-18/00-plan.md` phase by phase (A → G), in order.
Read `00-plan.md` and `decisions.md` fully first; decisions are settled — do not re-ask.

Hard rules:
- **Test-first proof**: for each phase, write the listed proof tests FIRST, run
  `cd CadenceCore && swift test`, and record in `current_state.md` that the new tests fail on
  current code (quote the failure). Then implement until the full suite is green. A phase
  without a recorded red→green cycle is not done.
- **Ship gate after EVERY phase, before starting the next**: swift test green → iOS
  `xcodebuild` build green → `scripts/check-test-pyramid.sh` green → update
  `plans/field-test-fixes/2026-07-18/current_state.md` → commit (conventional message +
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer) → merge to `main` →
  `git push origin main` → `gh run list --branch main --limit 1` and watch until CI is
  **green**. If CI fails, fix within the phase before moving on.
- Logic in `CadenceCore`/`CadenceFeatures` only; views stay thin. No new XCUITests.
  SessionView LOC ratchet (≤1102) must hold after Phase E.
- Coach hard rules apply: no new un-cited science claims; NFR-8 (suggest, don't proscribe)
  is the point of Phase C.
- When all seven phases are shipped and CI is green, do the closing pass in the plan and report
  every phase's commit SHA + CI status.
