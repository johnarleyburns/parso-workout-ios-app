# FR-2.3 — Pair a Bluetooth chest strap & capture live HR

> Pair a Bluetooth chest strap and capture live heart rate during any
> iPhone-recorded workout (see FR-4.4).

## Design
- `HeartRateMonitor` (CoreBluetooth, observable) connects to the standard Heart
  Rate Service (0x180D / 0x2A37), parses the measurement payload, auto-reconnects,
  and surfaces battery. Simulated mode emits a deterministic BPM stream for tests.
- During recording, `CardioRecorder` reads `hrm.currentBPM` each tick and appends
  an `HRSample`.

## Mockups
On the live record screen, a "Connect strap" affordance; once connected, a live
HR readout and zone replace it (matches the "Polar H10 connected" mockup).

## Implementation
1. `record.connectStrap` triggers `hrm.startScanning` + connect first device.
2. Live HR + zone shown when `currentBPM != nil`.
3. Full pairing/management UI lives under FR-4.4 (Settings).
- a11y ids: `record.connectStrap`, `record.hr`, `record.zone`.

## Automated testing
- **Unit:** `HeartRateMonitor.parseHeartRate` 8/16-bit + empty. (Done.)
- **UI:** start a workout, connect the (simulated) strap; assert a live HR
  readout appears.
