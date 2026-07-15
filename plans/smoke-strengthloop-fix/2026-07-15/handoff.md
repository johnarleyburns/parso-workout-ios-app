# Handoff — SmokeStrengthLoop set-row fix + duplicate simulator

Paste the block below into a fresh (non-plan-mode) coding session. Full analysis
is in `00-overview.md` in this directory.

---

**Task: fix the last failing UI smoke test + remove the duplicate iPhone 16 simulator.**

Context: `swift test` is fully green (1048 tests). The XCUITest smoke suite has
exactly one failure — `SmokeStrengthLoopTests.testLogWorkoutEndToEnd`. It asserts
the two logged Bench Press sets appear as `set.row.Bench Press.0` and `.1`, but the
completed-row id is `set.row.<name>.<workingNumber>` and `workingNumbers()` in
`Cadence/Cadence/Features/Train/SessionView.swift:342` is **1-indexed**
(`var n = 1`). Real ids are `.1` and `.2`. 1-indexing shipped 2026-06-22 (columnar
redesign); the `.0`/`.1` assertions were written 2026-07-12 against the old scheme,
so the test has been red since it was authored. 1-indexing is correct and
user-facing (every sibling id — `set.pending`, `set.editWeight`, `set.rpe`,
`set.editReps` — uses the same 1-based number), so fix the **test**, not the code.

Do:
1. In `Cadence/CadenceUITests/SmokeStrengthLoopTests.swift`: line 25
   `set.row.Bench Press.0` → `.1`; line 27 `set.row.Bench Press.1` → `.2`. Nothing
   else asserts numbered set rows. Do NOT touch `workingNumbers()`.
2. Delete the unpaired duplicate iPhone 16 simulator (keeps the watch-paired one so
   `name=iPhone 16` in `make smoke` / `Makefile:18` is unambiguous; CI picks by
   udid so it's unaffected):
   `xcrun simctl delete FC7B2F90-A27B-4BD5-9313-7B267636E165`

Verify:
- `xcrun simctl list devices available | grep "iPhone 16 "` → single iOS 18.1 device.
- `cd Cadence && xcodebuild test -project Cadence.xcodeproj -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CadenceUITests/SmokeStrengthLoopTests` → passes (proves the sets genuinely log/render as `.1`/`.2`).
- `make ci` → green.

Then run the CLAUDE.md post-task checklist: update `current_state.md`, commit
(`fix: correct 1-indexed set-row ids in SmokeStrengthLoop`), merge to `main`, push,
watch `gh run list --branch main --limit 1`, report SHA + CI status.

---
