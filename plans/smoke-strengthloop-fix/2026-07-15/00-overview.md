# Fix the last failing UI smoke test + remove duplicate iPhone 16 simulator

## Context

All 1048 `swift test` unit tests pass and 10 of 11 XCUITest smoke tests pass. One
test fails and one environment issue keeps biting:

1. **`SmokeStrengthLoopTests.testLogWorkoutEndToEnd` fails.** It logs two working
   sets of Bench Press, then asserts the completed rows appear under identifiers
   `set.row.Bench Press.0` and `set.row.Bench Press.1`. But the completed-set row
   id is `set.row.<name>.<workingNumber>`, and `workingNumbers()` in
   `Cadence/Cadence/Features/Train/SessionView.swift:342` is **1-indexed**
   (`var n = 1`). So the real ids are `set.row.Bench Press.1` and `.2`. The test's
   `.0`/`.1` assertions are stale.

   Timeline confirms it's a test bug, not a code regression: the 1-indexed
   numbering shipped 2026-06-22 (`6300ec4`, columnar set-entry redesign); the
   `.0`/`.1` assertions were written later, 2026-07-12 (`50d56b9`/`e9341a8`),
   against the old 0-indexed scheme. The test has been red since it was authored.
   1-indexing is the intended, user-facing scheme — every sibling id
   (`set.pending`, `set.editWeight`, `set.rpe`, `set.editReps`, `set.row`) uses the
   same 1-based `workingNumbers`/`workingNumber` value. So the test must move to
   the code, not the reverse.

2. **Two `iPhone 16` / iOS 18.1 simulators exist**, making
   `-destination 'platform=iOS Simulator,name=iPhone 16'` ambiguous. This is what
   `make smoke` uses (`Makefile:18`), so `make smoke` errors out before running
   any test ("multiple devices matched"). CI is unaffected — it selects the first
   available iPhone by udid (`.github/workflows/ios.yml:86`).

   - `iPhone 16` `14922B94-6522-49EB-B135-A9CFEDD2932E` — paired with Apple Watch Series 10 → **keep**
   - `iPhone 16` `FC7B2F90-A27B-4BD5-9313-7B267636E165` — unpaired duplicate → **delete**

Outcome: `make smoke` runs unambiguously and the full smoke suite goes green.

## Changes

### 1. Fix stale set-row identifiers in the test
File: `Cadence/CadenceUITests/SmokeStrengthLoopTests.swift`

- Line 25: `set.row.Bench Press.0` → `set.row.Bench Press.1` ("first logged set row").
- Line 27: `set.row.Bench Press.1` → `set.row.Bench Press.2` ("second logged set row").

No other test asserts numbered set rows (grep-verified), so nothing else changes.
Do **not** touch `workingNumbers()` — 1-indexing is correct and user-visible.

### 2. Delete the duplicate simulator
Run:

```
xcrun simctl delete FC7B2F90-A27B-4BD5-9313-7B267636E165
```

Local dev-environment change (recreatable via Xcode > Devices), keeping the
watch-paired iPhone 16. After deletion, `name=iPhone 16` resolves to one device.

### 3. (Optional hardening — confirm before doing)
Make `make smoke` immune to a future duplicate by pinning `SMOKE_DEST` to the
CI-style dynamic udid lookup, or documenting `SMOKE_DEST='id=<udid>'`. Not required
once the duplicate is gone.

## Verification

1. `xcrun simctl list devices available | grep "iPhone 16 "` shows a single
   iOS 18.1 iPhone 16.
2. Run the one fixed test end-to-end on a real simulator:
   ```
   cd Cadence && xcodebuild test -project Cadence.xcodeproj -scheme Cadence \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     -only-testing:CadenceUITests/SmokeStrengthLoopTests
   ```
   Expect `testLogWorkoutEndToEnd` to pass. (This also proves the sets genuinely
   log and render — the failing log only ever queried `.0`, so passing on
   `.1`/`.2` confirms the rows exist.)
3. Full local gate: `make ci` (runs `swift test` + `make smoke`). Expect green.
4. Post-task checklist (CLAUDE.md): update `current_state.md`, commit
   (`fix: correct 1-indexed set-row ids in SmokeStrengthLoop`), merge to `main`,
   push, watch `gh run list --branch main --limit 1`, report SHA + CI status.

## Notes / risks
- If step 2 still fails on `.1`/`.2`, the set isn't logging (deeper bug in the
  inline save flow) — but code review shows the flow is intact and only the
  assertion number is wrong, so this is not expected.
- The `set.row` id sits on a sibling of the `exerciseCard` leaf `Text`, not on the
  card container, so the "card collapses child ids" gotcha does not apply here.
- If the `Cadence` test plan includes `CadenceUITests`, CI has also been red on
  this test since 2026-07-12 — the same one-line fix clears it.
