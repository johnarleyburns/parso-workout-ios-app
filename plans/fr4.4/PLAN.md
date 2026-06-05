# FR-4.4 — Chest strap: discover, connect, reconnect, battery, remember

> Chest strap: discover, connect, and subscribe to a BLE HRM via the standard
> Heart Rate Service (0x180D / characteristic 0x2A37); reconnect automatically;
> surface battery and signal status; persist a remembered device.

## Design
- `HeartRateMonitor` (CoreBluetooth) handles discovery, connect, 0x2A37 notify,
  battery (0x180F/0x2A19), and auto-reconnect on disconnect. Simulated mode for
  the simulator yields two fake devices and a BPM stream.
- A remembered device is persisted as `HRMDevice` (id, name, battery, isDefault)
  in SwiftData and reconnected on launch.

## Mockups
Settings → Heart-Rate Monitor: "My Device" (default, battery, connected),
"Discovered Devices" each with a Connect button (matches the mockup).

## Implementation
1. `HRMSettingsView`: scan on appear, list `hrm.discovered`, Connect saves an
   `HRMDevice` default; show battery + live BPM + connection state.
- a11y ids: `settings.hrm`, `hrm.scan`, `hrm.connect.<name>`, `hrm.myDevice`,
  `hrm.battery`, `hrm.bpm`.

## Automated testing
- **Unit:** `parseHeartRate` (8/16-bit). (Done.)
- **UI:** open Settings → Heart-Rate Monitor → Scan → Connect a device → assert
  "My Device" + a live BPM appear.
