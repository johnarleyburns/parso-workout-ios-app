# W2 — Units on the wrist (lb/kg)

Fixes user report **3**: lifts default to kg with no way to change it.

## What the code does today

- `WatchStrengthView.swift:141` renders `String(format: "%.0f kg", weight)`;
  chips step ±5, Crown steps 2.5 — all implicitly kg.
- The model layer is fine: `SetEntry` stores kg internally, and
  `MeasurementUnitPreference` (kg/lb, `WorkoutMath.swift:92`) +
  `Format.weightValue/setLineDual` (CadenceFeatures) already do conversion and
  display on the phone.
- `AppSettings` (CadenceFeatures) persists `unit` in `UserDefaults` — but the
  watch has **its own** UserDefaults; the phone's choice never reaches it, and
  the watch Settings screen has no Units row.

## Research signal
- Phone default: `SettingsDefault.unit` — the watch must end up agreeing with the
  phone, not maintain a rival preference.
- `Locale.measurementSystem == .us` is the correct first-run default (→ pounds
  for the user; kg elsewhere) when no phone context has arrived yet.
- v2 already planned "settings sync" via `updateApplicationContext` (Phase 5,
  unshipped). This is the first concrete consumer.

## Design

**Single source of truth: the phone.** The watch keeps a local copy that is
(1) seeded from locale on first run, (2) overwritten whenever the phone pushes
context, (3) user-editable on the watch — and a watch-side edit pushes **back**
to the phone so the two never disagree.

- **Watch Settings → Units row**: "Pounds (lb)" / "Kilograms (kg)" picker
  (reuses `MeasurementUnitPreference.displayName`).
- **Phone → watch**: phone calls `updateApplicationContext(["settings.unit": …,
  "settings.colorBlind": …, "settings.restSeconds": …, "settings.cooldownMinutes": …])`
  on every settings change and on WC activation (context is latest-value,
  delivered even if the watch was asleep). Watch applies it in
  `didReceiveApplicationContext`. *(Decision D2, settled: sync all four now.)*
- **Watch → phone**: watch edit sends `transferUserInfo(["action": "set_unit", …])`
  (guaranteed delivery); phone applies to `AppSettings.unit`.
- **Entry ergonomics by unit** (new pure helper `WeightIncrement` in
  CadenceFeatures):
  - lb: chips ±5 lb, Crown detent 2.5 lb, range 0–650 lb
  - kg: chips ±2.5 kg, Crown detent 1.25 kg, range 0–300 kg
  - Internally the bound value stays **kg** (model truth); display/steps convert
    at the edge via `Format`.
- Everywhere weight appears on the watch (keypad, "Previous: 135 × 8", summary),
  render via `Format.weightValue(_:unit:)` — no raw `"kg"` literals left
  (grep-able acceptance criterion).

## Data-model deltas
- None in SwiftData (kg-internal storage unchanged; exports unaffected).
- New WC keys: applicationContext `settings.unit` (+ future settings.*);
  userInfo action `set_unit`. Both additive.
- New watch UserDefaults key `watch.settings.unit` via a shared `AppSettings`
  instance on the watch.

## Implementation steps
1. `WeightIncrement` (pure, CadenceFeatures): chips/detent/range per unit +
   locale-based default. Headless tests.
2. Watch: instantiate `AppSettings` (it's already in CadenceFeatures, which the
   watch links); seed unit from locale when the stored value is absent.
3. WC plumbing: phone pushes context on settings change + activation; watch
   applies + reflects; watch edits round-trip via `set_unit`.
4. Watch Settings gains the Units section (top of the list — the Settings-append
   convention is a phone-UI-test constraint and doesn't bind the watch, but keep
   HR Source first since it's the more-used row; Units second).
5. Sweep `WatchStrengthView` for literals; route all display through `Format`.

## Testing
- `swift test`: `WeightIncrement` (both units, locale default, range clamps),
  context-apply merge logic (pure reducer: (localPrefs, contextDict) → prefs).
- Device: set lb on phone → watch keypad shows lb within seconds; change to kg
  on watch → phone Settings reflects it.

## Open questions
None — D2 settled (all four settings ride in the first context push).
