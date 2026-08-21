# P6 — HR gate "Continue without heart rate" always tappable (field-test issue 6)

## Problem

> On the cardio "Connect Heart Rate" view, "Continue without heart rate" should
> still be clickable even if my Apple Watch has a connection issue; currently it
> just makes the screen inoperable.

## What the code does today

`PreWorkoutHRView.swift`:

- "Check for Live HR" — `:68-75`: disabled while the relay is `.connecting` or
  `.waitingForSample` (`:73`).
- "Continue…" — `:101-116`:
  ```swift
  Button {
      if watchBPM == nil { model.stopWatchWorkout() }
      if watchBPM != nil { onContinue(.watch) }
      else if strapConnected { onContinue(.bluetooth) }
      else { onContinue(.none) }
  } label: {
      Text(watchBPM != nil ? "Continue with Apple Watch"
           : (strapConnected ? "Continue with Bluetooth" : "Continue without heart rate"))
      ...
  }
  .disabled(watchSelected && watchBPM == nil && !strapConnected)   // :114  ← the bug
  .accessibilityIdentifier("prehr.start")
  ```

After the user taps "Check for Live HR" (`watchSelected = true`), if the watch
never delivers a sample (connection issue, the P5 stale-session rejection, or a
slow strap), `watchBPM` stays `nil` and no strap is connected → the primary
action is **disabled forever**. The screen's only meaningful button does nothing
→ "inoperable". The 15 s timeout eventually flips the relay to `.timedOut`, but
`watchSelected` remains `true` and the disable condition still holds — the
button stays dead even after the timeout.

## Design

### The Continue action is always available

Remove the `.disabled(...)` at `PreWorkoutHRView.swift:114`. The button already
behaves correctly for every state:

- live watch BPM → `onContinue(.watch)` (session stays active).
- strap connected → `onContinue(.bluetooth)`.
- neither → `onContinue(.none)`, and `model.stopWatchWorkout()` first (line 103)
  so a pending/leaked watch session is torn down — this is the NFR-8 escape
  hatch P5 depends on.

Label logic stays (watch / bluetooth / none). When the relay is still
`.connecting`/`.waitingForSample` and the user proceeds without HR, the
`stopWatchWorkout()` call cancels the relay cleanly.

### "Check for Live HR" no longer blocks on transient states

Change `:73` so the button is **never disabled** by `.connecting` /
`.waitingForSample`. Each tap begins a fresh `start_workout` with a new
requestID (`AppModel.startWatchWorkout` already re-arms the relay via `begin`);
the existing 15 s timeout and P5B's `.alreadyActive` recovery keep it honest.
A tap during a stuck relay is exactly the recovery action the user wants to be
able to take.

### Extract the decision to a pure presenter (headless-testable)

Move the label + enabled + source logic out of the view into a new CadenceFeatures
type so it is `swift test`-able:

```swift
// CadenceFeatures — PreWorkoutHRPresenter.swift
public enum PreWorkoutHRContinue { case watch, bluetooth, none }
public struct PreWorkoutHRState: Equatable, Sendable {
    public var watchBPM: Int?
    public var strapConnected: Bool
    public var watchRequested: Bool      // was "Check for Live HR" tapped
    public var relayBusy: Bool           // connecting / waitingForSample
}
public enum PreWorkoutHRPresenter {
    public static func continueLabel(_ s: PreWorkoutHRState) -> String   // "Continue with Apple Watch" / "…Bluetooth" / "…without heart rate"
    public static func continueEnabled(_ s: PreWorkoutHRState) -> Bool    // ALWAYS true — the fix
    public static func continueAction(_ s: PreWorkoutHRState) -> PreWorkoutHRContinue
    public static func checkEnabled(_ s: PreWorkoutHRState) -> Bool       // ALWAYS true — never blocks on transient relay states
}
```

`HRSourceChoice` currently lives in the app target (`PreWorkoutHRView.swift:6`);
the presenter's `PreWorkoutHRContinue` is the CadenceFeatures semantic enum the
view maps to the existing `HRSourceChoice`.

## Data-model deltas

None. New pure presenter type only.

## Implementation steps

1. Add `CadenceCore/Sources/CadenceFeatures/PreWorkoutHRPresenter.swift`
   (Foundation-only).
2. `PreWorkoutHRView`: drive the label, the `prehr.start` action, and the two
   button enable states from the presenter; delete `.disabled(...)` and the
   `:73` transient disable. `onContinue` maps `PreWorkoutHRContinue` → the
   existing `HRSourceChoice`.
3. Run `swift test`.

## Testing

### Unit tests (CadenceFeaturesTests — `PreWorkoutHRPresenterTests`, new)

- `testContinueIsEnabledWithNoHRAndWatchRequested` — the exact reported state
  (`watchRequested = true`, `watchBPM = nil`, no strap) → `continueEnabled == true`.
- `testContinueIsEnabledWhileRelayBusy` — `.connecting`/`.waitingForSample` →
  still enabled.
- `testContinueActionWatchWhenLive` — live watch BPM → `.watch`.
- `testContinueActionBluetoothWhenStrapConnected` → `.bluetooth`.
- `testContinueActionNoneWhenNothingConnected` → `.none`.
- `testContinueLabelMatchesAction` — all three labels.
- `testCheckHRAlwaysEnabled` — `checkEnabled` true regardless of state.

### iPhone smoke test — fold into P5's smoke addition

The P5 smoke addition already enters the HR gate for a timer cardio workout; add
the P6 assertions there:

- `prehr.start` **exists and is enabled** before any watch connection
  (`isEnabled` is assertable in XCUITest).
- Optionally: tap "Check for Live HR" (no real watch in the simulator → the
  relay will fail/timing out), then assert `prehr.start` is **still enabled**
  — the exact field report end-to-end.

If P5's smoke growth is declined, keep P6 headless-only (the presenter tests are
the real coverage).

## Open questions

- None. This is decision-backed by NFR-8 (the escape hatch must never be
  disabled by a failed sensor connection).
