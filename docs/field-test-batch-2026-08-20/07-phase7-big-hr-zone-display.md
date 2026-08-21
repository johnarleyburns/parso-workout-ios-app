# P7 — Big, bold, zone-colored HR display on cardio (field-test issue 7)

## Problem

> On cardio exercises with HR monitoring active (Bluetooth chest strap or Apple
> Watch), don't show BPM and zone as simple text with an average; show a VERY
> LARGE FONT BOLD HR number colored by zone (same color scheme as the Apple
> Watch), with smaller text underneath for zone and average BPM. Easy to read at
> a glance.

## What the code does today

- **Watch zone color scheme** (the target scheme): Z1 **cyan**, Z2 **green**,
  Z3 **yellow**, Z4 **orange**, Z5 **red**.
  - `WatchRootView.swift:331` (`zoneColor`), `WatchCardioView.swift:81-89`
    (`zoneBackgroundColor`). Zone label vocab on watch: Recovery / Endurance /
    Tempo / Threshold / Max.
- **Phone cardio HR display — small text today:**
  - `RecordCardioView.liveScreen` (`RecordCardioView.swift:104-112`): HR/Zone/
    Avg HR as three `metric(...)` grid cells (`record.hr`, `record.zone`,
    `record.avgHr`).
  - `OutdoorCardioView` (`OutdoorCardioView.swift:94`): `bigMetric(Format.heartRate(recorder?.currentBPM), "Heart Rate", id: "outdoor.hr")` — no zone, no color.
  - `IntervalView` (`IntervalView.swift:87-91`): `Label("\(Int(bpm)) bpm", systemImage: "heart.fill")` (`interval.bpm`).
- **Data is already there:** `CardioRecorder.currentBPM: Double?`, `avgHR: Double?`,
  `zone: Int` (`CardioRecorder.swift:74-88`), `CardioMath.zoneName(_:)`
  (`CardioMath.swift:21-29`, "Recovery/Easy/Aerobic/Threshold/Max"). `maxHR`
  defaults to 190 in the recorder; the zone math is `CardioMath.hrZone`.

## Design

### Shared live-HR readout component

New app-target view `Cadence/Cadence/Features/Cardio/LiveHRBigView.swift`:

- Inputs: `bpm: Double?`, `zone: Int` (0 when no BPM), `avgHR: Double?`,
  `idPrefix: String`, optional `label` override.
- Renders:
  ```
   ♥  143                          ← very large bold monospaced, zone color
     Z3 · Aerobic · Avg 138 bpm    ← smaller, zone color for the zone part
  ```
  - BPM number: `.system(size: 84, weight: .heavy, design: .rounded)`
    (Dynamic-Type aware via `scaledSystemFont`), `monospacedDigit`, foreground =
    zone color. Id `<prefix>.hr`.
  - Zone line: `Z<n> · <zoneName>` in the zone color + ` · Avg <bpm> bpm` in
    secondary (id `<prefix>.zone`). Avg text id `<prefix>.avgHr`.
  - No BPM → `—` in secondary and the zone line shows `No heart rate yet`
    (id `<prefix>.zone`), so the layout is stable from the start and the
    "only when HR monitoring is active" requirement is satisfied by keeping the
    component always mounted (HR off = muted `—`, not missing).
- `accessibilityElement(children: .combine)` with label
  `<bpm> beats per minute, zone <n>, average <avg>`.

### Zone → color mapping (semantic, headless-testable)

CadenceFeatures cannot return `Color`; add a semantic enum:

```swift
// CadenceFeatures — HRZoneTint.swift
public enum HRZoneTint: Equatable, Sendable {
    case zone1, zone2, zone3, zone4, zone5, neutral
    public static func tint(for zone: Int) -> HRZoneTint {
        switch zone { case 1: .zone1; case 2: .zone2; case 3: .zone3
                      case 4: .zone4; case 5: .zone5; default: .neutral }
    }
}
```

View-side `Color(hrZoneTint:)` maps to the **watch scheme**:
`zone1 = .cyan`, `zone2 = .green`, `zone3 = .yellow`, `zone4 = .orange`,
`zone5 = .red`, `neutral = .secondary`. (Documented as "same as the Apple Watch"
so future surfaces reuse it; the watch target keeps its own hard-coded mapping
unless a later refactor shares this.)

Also add a pure subtitle builder in CadenceFeatures (used by the component):

```swift
public enum LiveHRPresenter {
    /// "Z3 · Aerobic · Avg 138 bpm" — zone + zoneName + optional average.
    public static func subtitle(zone: Int, avgHR: Double?) -> String
    public static func bpmText(_ bpm: Double?) -> String   // "143" or "—"
}
```

### Use it on all three cardio live screens

- `RecordCardioView.liveScreen` (`RecordCardioView.swift:104-112`): replace the
  HR / Zone / Avg HR `metric` cells with `LiveHRBigView(bpm: recorder.currentBPM, zone: recorder.zone, avgHR: recorder.avgHR, idPrefix: "record")`. Keep Distance/Pace in the grid for GPS types. Preserve the identifiers `record.hr`, `record.zone`, `record.avgHr` on the component.
- `OutdoorCardioView` (`:94`): replace the `bigMetric` HR cell with
  `LiveHRBigView(..., idPrefix: "outdoor")` (keeps `outdoor.hr`).
- `IntervalView` (`:87-91`): replace the `Label` with
  `LiveHRBigView(..., idPrefix: "interval")` (keeps `interval.bpm`).

The strength surface (`SessionLiveHRBand`, `SessionInfoSheets.swift:13-41`)
stays as its compact band — the user asked for the cardio surfaces.

## Data-model deltas

None. New view + two small CadenceFeatures types.

## Implementation steps

1. `CadenceFeatures/HRZoneTint.swift` + `LiveHRPresenter` (or fold the subtitle
   builder into the tint file; keep each file under 400 LOC).
2. App target: `Color(hrZoneTint:)` mapping + `LiveHRBigView`.
3. Wire into `RecordCardioView`, `OutdoorCardioView`, `IntervalView`.
4. `swift test` + build.

## Testing

### Unit tests (CadenceFeaturesTests)

- `HRZoneTintTests`:
  - `testTintMappingMatchesWatchScheme` — 1→zone1 … 5→zone5, 0/6/‑1→neutral.
  - `testSubtitleZones` — "Z3 · Aerobic", "Z5 · Max" (+ average suffix).
  - `testSubtitleNilAverageOmitsSuffix`.
  - `testBpmText` — "143" / "—".
- `CardioMath.hrZone` boundary tests already exist for the underlying math.

### iPhone smoke test — no change

The smoke flow does not run a live cardio screen with HR (no simulator HR
source), so a zone-color assertion would be vacuous. Headless + visual
verification on the simulator (screenshot of `record.hr` with a mocked BPM if a
fake `HeartRateMonitoring` seam is easy; otherwise a real strap/device check).
Note: the P5 smoke addition's timer-cardio leg could assert `record.hr` exists
(rendering `—`), a cheap structural check if that leg lands.

## Open questions

- Whether `IntervalView` (HIIT/boxing) should use the same big display. The user
  said "on cardio exercises" and HIIT/boxing are cardio; include it (decision
  **D6** in `decisions.md`).
- Whether the big display should also show on the strength live band. The user
  scoped it to cardio; leave strength as-is unless the user says otherwise.
