# FR-2.2 — Record an iPhone-only workout (GPS outdoor / manual indoor)

> Record an iPhone-only outdoor workout using GPS for route/distance/pace
> (running, cycling) and a manual timer for indoor (boxing, etc.).

## Design
- `LocationTracker` (CoreLocation, observable; simulated mode synthesizes a
  moving track). `GeoMath.pathDistance` computes distance from fixes.
- `CardioRecorder` (observable) ties together an elapsed timer, the location
  tracker (for GPS types), and the HR monitor; accumulates samples.
- Outdoor types (`CardioType.usesGPS`) start GPS; indoor types use the timer
  only.

## Mockups
Cardio tab → "Record" → pick activity → live screen with a big timer; for GPS
types also distance + pace. Start/Pause/End.

## Implementation
1. `CardioRecorder` start/pause/resume/end.
2. `RecordCardioView` activity picker + live metrics + controls.
3. `GeoMath`/`CardioMath` for distance + pace.
- a11y ids: `cardio.record`, `record.start.<type>`, `record.elapsed`,
  `record.distance`, `record.pause`, `record.end`.

## Automated testing
- **Unit:** `GeoMath.pathDistance`, `CardioMath.paceSecPerKm`. (Done.)
- **UI:** start an outdoor run; assert elapsed advances and distance appears;
  end; assert the workout lands in history.
