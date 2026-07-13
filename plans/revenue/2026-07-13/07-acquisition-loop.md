# Phase 6 — The acquisition loop

**Branch:** `phase-6-acquisition-loop`
**Depends on:** Phase 0.
**Decision:** D6.

---

## Problem

**Cladiron has no growth loop at all.** Every install has to be earned from scratch.
Hevy's social feed is its moat — apps with social features see 20–35% lower monthly
churn than solo experiences.

But building a social graph requires accounts and a server, and would destroy the
positioning outright. So don't.

**Build the 10% that captures most of the value: something worth sharing, and a way
to share it.**

There is a happy accident here — **`CLAUDE.md` already claims a PR timeline and a
consistency heatmap in the Progress IA. Neither exists.** PR logic currently lives
inline in `SessionView` and `WorkoutRepository.currentPR`. Lift it into pure code and
the claim becomes true, the Progress tab gets its emotional payload, and the share
card gets something worth putting on it.

---

## Steps

### 1. New `CadenceCore/Sources/CadenceCore/PRTimeline.swift`

Pure. Lift the PR-detection logic out of `SessionView` / `WorkoutRepository.currentPR`
rather than reimplementing it — reuse the existing `PRRule` so the timeline and the
in-session PR badge can never disagree.

```swift
public struct PREvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let exerciseName: String
    public let date: Date
    public let kind: PRKind        // .weight, .e1RM, .reps, .volume
    public let value: Double
    public let previous: Double?
}

public enum PRTimeline {
    public static func events(sessions: [WorkoutSessionSnapshot],
                              rule: PRRule) -> [PREvent]
}
```

### 2. New `CadenceCore/Sources/CadenceCore/ConsistencyHeatmap.swift`

Pure.

```swift
public struct HeatmapDay: Sendable, Equatable {
    public let date: Date
    public let sessionCount: Int
    public let intensity: Int    // 0...4, for the colour ramp
}

public enum ConsistencyHeatmap {
    public static func days(sessionDates: [Date],
                            range: DateInterval,
                            calendar: Calendar) -> [HeatmapDay]
}
```

Take `Calendar` as a parameter — do not reach for `.current` inside. That is what
makes the DST and timezone tests possible.

### 3. `CadenceFeatures` — presenters

`PRTimelinePresenter`, `ConsistencyHeatmapPresenter`.

Return **semantic enums** for the colour ramp — **never `Color`**. `CadenceFeatures`
may not import SwiftUI, and `scripts/check-test-pyramid.sh` fails CI if it does. The
view maps the enum to a colour.

### 4. UI

`Features/Progress/PRTimelineView.swift` and
`Features/Progress/ConsistencyHeatmapView.swift` (Swift Charts), linked from the
Progress tab.

### 5. The loop — a shareable PR card

`Features/Share/ShareCardRenderer.swift`: a SwiftUI card rendered through
`ImageRenderer` → a branded PNG → `ShareLink`.

**No account. No server. Nothing leaves the device but an image the user explicitly
chose to post.** A genuine acquisition loop at zero privacy cost — and one that
reinforces the brand rather than compromising it.

### 6. `CLAUDE.md`

Restore the PR-timeline and consistency-heatmap lines to the Progress IA (removed in
Phase 0), now that they are true.

---

## Tests

**`PRTimelineTests`**
- a first-ever lift **is** a PR
- ties are **not** PRs
- a heavier single beats a lighter double on e1RM
- bodyweight lifts
- per-exercise independence (a squat PR does not affect bench)
- correct chronological ordering
- **warmup sets are excluded**

**`ConsistencyHeatmapTests`**
- day bucketing
- week boundaries
- **DST transitions** (the classic off-by-one-day bug)
- timezone changes
- an empty range
- multiple sessions in one day
- the intensity ramp saturates at 4

**Presenter tests** in `CadenceFeaturesTests`.

---

## Acceptance

- `swift test` green.
- `scripts/check-test-pyramid.sh` green — **no new UI tests**, and no `Color` in
  `CadenceFeatures`.
- The PR timeline and consistency heatmap render in the Progress tab.
- The share sheet produces a PNG.
- `CLAUDE.md`'s Progress IA is true again.

## Commit

```
feat: PR timeline, consistency heatmap, and a shareable PR card (the only zero-privacy-cost growth loop)
```
