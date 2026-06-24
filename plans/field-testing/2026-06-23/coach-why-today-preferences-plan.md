# Coach Why This Today + Preference Learning Plan

**Date:** 2026-06-23  
**Stream:** `plans/field-testing/2026-06-23/`  
**Mockup:** `docs/coach-why-today-preferences-mockups.html`  
**Scope:** Fix the "Why this today" explanation surface, add a visible Coach's Pick prescription with alternatives, remember user-selected alternatives, and export those preferences transparently.

## Product Goal

When Coach prescribes a session, the user should be able to answer four questions immediately:

1. What did Coach observe?
2. What exactly is Coach asking me to do today?
3. What else would satisfy the same prescription if this option does not fit me?
4. What preferences has Coach learned from my choices, and can I export them?

This must remain deterministic, local, explainable, and cited. Do not introduce an LLM or server-side profile.

## Field-Test Problems

### A. What You Did Is Incomplete And Ticking

Current behavior:

- `WhyThisTodayView` shows `What you did`.
- It is missing Last Cardio.
- Weekly facts such as `1 strength day this week` and `18 / 150 moderate-equivalent minutes` show a live second-by-second relative timer on the right.

Cause:

- `CoachDecisionEngine` builds `observedFacts` in `CadenceCore/Sources/CadenceCore/CoachDecision.swift`.
- It only adds last strength and weekly summary rows.
- Weekly summary rows use `timestamp: now`.
- `WhyThisTodayView` renders every fact using `Text(fact.timestamp, style: .relative)`, which ticks because SwiftUI keeps relative dates live.

Expected behavior:

- `What you did` includes Last Strength when present.
- `What you did` includes Last Cardio when present.
- Weekly summary facts show static values, not a ticking relative clock.
- Only true event facts show a static relative recency string, for example `2h ago`.

### B. Science Is Duplicated

Current behavior:

- The screen can show multiple compact `The science >` links inline.
- It can also show an `Evidence` section with one or more of the same citations.

Cause:

- `WhyThisTodayView` renders citations inline in `Why this won`.
- It also renders `Section("Evidence")` from `decision.citationIds`.

Expected behavior:

- No generic `Evidence` section when citations already appear inline.
- Citations live next to the claim they support.
- If future citations are not tied to any claim, show `Additional sources`, but only for citations not already displayed.

### C. Coach's Prescription Is Missing

Current behavior:

- Why This Today explains some scoring, but does not show the actual prescription as its own section.
- `CoachDecision` already has `primary` and `alternatives`, but the view does not expose them clearly.

Expected behavior:

- Add a section immediately after `What you did` titled exactly `COACH'S PICK`.
- Show the selected exercise/session, duration, intensity, and target details.
- Add an `alternatives >` row at the bottom.
- Alternatives should include options that fulfill the same prescription completely when possible, or most closely when recovery/safety constraints apply.

Example:

- Coach's Pick: `Steady run`
- Alternatives: `Brisk walk`, `Cycle`, `Swim`, `Row`, `Boxing`
- If the user picks `Cycle`, Coach should remember that preference and prefer cycling next time it needs a similar moderate aerobic prescription, assuming cycling is eligible.

### D. Learned Preferences Must Be Exported

Current behavior:

- Settings -> Data -> Export exports sessions and cardio.
- Coach preference/profile data does not exist.

Expected behavior:

- Learned Coach preferences are included in JSON export.
- Export UI copy should make clear that these preferences are part of the user's data.
- Import must remain backward-compatible with older exports that lack preference data.

## Current Code Map

Primary files:

- `CadenceCore/Sources/CadenceCore/CoachDecision.swift`
  - `CoachDecision`
  - `ObservedFact`
  - `CoachDecisionEngine.run`
- `CadenceCore/Sources/CadenceCore/CoachSession.swift`
  - `CoachSession`
  - `CoachSession.candidates(for:)`
  - Existing cardio candidates are too narrow for alternatives.
- `CadenceCore/Sources/CadenceCore/CoachFacts.swift`
  - Builds rolling windows and weekly balance.
- `CadenceCore/Sources/CadenceCore/TrainingEvent.swift`
  - Converts strength/cardio SwiftData rows into coach facts.
- `Cadence/Cadence/Features/Coach/WhyThisTodayView.swift`
  - Current explanation UI.
- `Cadence/Cadence/Features/Home/HomeView.swift`
  - Builds `CoachDecision`; navigates to `WhyThisTodayView`.
- `Cadence/Cadence/App/AppSettings.swift`
  - Existing UserDefaults-backed settings. Best place for a small Codable Coach profile.
- `CadenceCore/Sources/CadenceCore/DataExport.swift`
  - Add export DTOs for Coach preferences.
- `CadenceCore/Sources/CadenceCore/WorkoutRepository.swift`
  - Update `buildExport`.
- `Cadence/Cadence/Features/Settings/ExportView.swift`
  - Pass settings/profile into export.
- `Cadence/Cadence/App/UITestSeed.swift`
  - Add deterministic seeds for UI tests.

## Non-Goals

- Do not add cloud inference, telemetry, accounts, or server storage.
- Do not infer medical diagnoses. If the user selects cycling instead of running, store a modality preference. Do not label it as knee pain unless the user explicitly marks high-impact avoidance.
- Do not remove the existing recovery and pain eligibility gates.
- Do not make preferences override hard safety or recovery rules.
- Do not build a general profile UI unless needed for the alternatives flow and export transparency.

## Data Model Plan

### 1. Replace Or Extend ObservedFact

Current:

```swift
public struct ObservedFact: Sendable, Equatable {
    public let label: String
    public let timestamp: Date
}
```

Proposed:

```swift
public struct ObservedFact: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case lastStrength
        case lastCardio
        case weeklyStrengthDays
        case weeklyModerateEquivalentMinutes
        case hardDays
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let value: String
    public let detail: String?
    public let occurredAt: Date?
}
```

Rules:

- Event facts use `occurredAt` plus a preformatted `value`, such as `2h ago`.
- Summary facts set `occurredAt = nil` and static values, such as `1 / 2+`.
- `WhyThisTodayView` must never call `Text(date, style: .relative)` for observed facts.

### 2. Add Coach Preference Profile

Create a new file:

- `CadenceCore/Sources/CadenceCore/CoachPreferenceProfile.swift`

Proposed core types:

```swift
public struct CoachPreferenceProfile: Codable, Equatable, Sendable {
    public var version: Int
    public var aerobicPreferences: [AerobicPreference]
    public var strengthPreferences: [StrengthPreference]
    public var avoidedTags: [String]
    public var selectionEvents: [CoachPreferenceEvent]
}

public struct AerobicPreference: Codable, Equatable, Sendable {
    public var intent: CoachPrescriptionIntent
    public var modality: CoachSession.AerobicModality
    public var score: Int
    public var updatedAt: Date
}

public struct StrengthPreference: Codable, Equatable, Sendable {
    public var pattern: MovementPattern
    public var exerciseName: String
    public var score: Int
    public var updatedAt: Date
}

public struct CoachPreferenceEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var selectedSessionId: String
    public var selectedTitle: String
    public var selectedKind: CoachSessionKind
    public var selectedModality: CoachSession.AerobicModality?
    public var intent: CoachPrescriptionIntent
    public var alternativeIdsShown: [String]
    public var createdAt: Date
}

public enum CoachPrescriptionIntent: String, Codable, Sendable {
    case easyAerobic
    case moderateAerobic
    case vigorousIntervals
    case recovery
    case strengthPattern
    case rest
    case assessment
}
```

Implementation notes:

- Make `CoachSession.AerobicModality` and `CoachSessionKind` conform to `Codable`.
- If making nested types Codable is noisy, create export/storage raw-value DTOs instead.
- Keep profile mutation pure in `CadenceCore`, for example:

```swift
public mutating func recordSelection(_ session: CoachSession, from alternatives: [CoachSession], at date: Date)
```

### 3. Persist Profile In AppSettings

In `Cadence/Cadence/App/AppSettings.swift`:

- Add `var coachPreferenceProfile: CoachPreferenceProfile`.
- Store as JSON `Data` in UserDefaults under `settings.coachPreferenceProfile`.
- Clear the key in `-uiTest` mode.
- Add helpers:

```swift
func recordCoachSelection(_ session: CoachSession, alternatives: [CoachSession], at date: Date = Date())
```

Do not store this in SwiftData for the first implementation. It is a compact settings/profile object, and it needs to be exported explicitly.

## Coach Decision Plan

### 1. Add Profile Input

Change:

```swift
public static func run(_ facts: CoachFacts, hasPainConcern: Bool = false) -> CoachDecision
```

To:

```swift
public static func run(
    _ facts: CoachFacts,
    profile: CoachPreferenceProfile = .empty,
    hasPainConcern: Bool = false
) -> CoachDecision
```

Update call sites in `HomeView`.

### 2. Expand Candidate Generation

In `CoachSession.candidates(for:)`, add more aerobic options:

- Easy:
  - Easy walk
  - Easy cycle
  - Easy swim
  - Easy row
- Moderate:
  - Brisk walk
  - Steady run
  - Steady cycle
  - Steady swim
  - Row
  - Boxing conditioning
- Vigorous:
  - VO2 intervals
  - Bike intervals
  - Row intervals if supported by current launch routes

Each candidate needs:

- Stable `id`.
- `kind`.
- `title`.
- `subtitle`.
- `durationMinutes`.
- `modality`.
- `intensity`.
- `trainingLoadTags`, including impact and target intent, for example `["aerobic", "moderate", "lowImpact"]`.
- `citationIds`.
- `launchPayload`.

Do not add candidates that cannot launch unless they are explicitly marked informational. Prefer launchable candidates.

### 3. Add Intent And Fulfillment Classification

Add a pure helper in `CadenceCore`:

```swift
public enum AlternativeMatch: String, Sendable, Equatable {
    case full
    case close
    case recoveryAdjusted
}
```

Expose enough data for the UI to say:

- `Fully matches today's aerobic target`
- `Closest low-impact match`
- `Recovery-adjusted option`

This can be derived from session kind, intensity, duration, modality, and load tags.

### 4. Score Preferences After Eligibility

Eligibility must run first.

Suggested scoring order:

1. Hard gates: pain, active workout, recovery windows, lower-body collision.
2. Base score: weekly strength and aerobic gaps.
3. Preference adjustment:
   - Add points when the session modality matches learned preference for the same intent.
   - Add points when the strength exercise matches learned preference for the same movement pattern.
   - Subtract points for explicit avoided tags.
4. Tie-breaks:
   - Safer/lower impact first when score is equal.
   - Stable `id` ordering last for determinism.

Acceptance rule:

- A learned preference can reorder eligible candidates.
- A learned preference cannot make an ineligible candidate primary.

## UI Plan

### 1. Why This Today Structure

Update `WhyThisTodayView` section order:

1. `What you did`
2. `COACH'S PICK`
3. `What Coach ruled out`
4. `Why this won`
5. `Coach Warnings`
6. `Policy`

Remove generic `Evidence` in the normal case.

### 2. What You Did Row Format

Example rows:

- `Last strength` | `Back Squat + Bench Press · 2h ago`
- `Last cardio` | `Run · 18 min · yesterday`
- `Strength days this week` | `1 / 2+`
- `Moderate-equivalent minutes` | `18 / 150`

Add accessibility identifiers:

- `whyToday.fact.lastStrength`
- `whyToday.fact.lastCardio`
- `whyToday.fact.strengthDays`
- `whyToday.fact.moderateEquivalentMinutes`

### 3. Coach's Pick Section

Create a reusable local view, or a small new file:

- `Cadence/Cadence/Features/Coach/CoachPickSection.swift`

Expected content:

- `decision.primary.title`
- `decision.primary.subtitle`
- Duration/intensity row when available.
- Strength exercise rows when available.
- `alternatives >` button at bottom.

Accessibility identifiers:

- `whyToday.coachPick`
- `whyToday.coachPick.title`
- `whyToday.coachPick.alternatives`

### 4. Alternatives View

Create:

- `Cadence/Cadence/Features/Coach/CoachAlternativesView.swift`

Routes:

- Add `case coachAlternatives` to `HomeRoute`, or present from `WhyThisTodayView`.
- The alternatives view needs access to the current `CoachDecision`, current profile, and a selection callback.

Rows:

- Title.
- Why it matches.
- Duration/intensity.
- `Choose` action.

On choose:

1. Record selection into `settings.coachPreferenceProfile`.
2. Launch selected session or return to Home with selected session as primary, depending on the simplest UX path.
3. At minimum, after returning Home, the next `CoachDecisionEngine.run` should produce the selected modality as primary for the same prescription if still eligible.

Recommended first implementation:

- Selecting an alternative records the preference and launches that alternative.
- The next recompute naturally makes it the Coach's Pick.

Accessibility identifiers:

- `coach.alternatives`
- `coach.alternatives.row.<session.id>`
- `coach.alternatives.choose.<session.id>`
- `coach.alternatives.match.<session.id>`

## Export Plan

### 1. Add Export DTOs

In `DataExport.swift`:

```swift
public struct CadenceExport: Codable, Equatable, Sendable {
    public var version: Int
    public var exportedAt: Date
    public var sessions: [ExportSession]
    public var cardio: [ExportCardio]
    public var coachPreferences: ExportCoachPreferences?
}
```

Set:

```swift
public static let currentVersion = 2
```

Add:

```swift
public struct ExportCoachPreferences: Codable, Equatable, Sendable {
    public var profileVersion: Int
    public var aerobicPreferences: [ExportAerobicPreference]
    public var strengthPreferences: [ExportStrengthPreference]
    public var avoidedTags: [String]
    public var selectionEvents: [ExportCoachPreferenceEvent]
}
```

Keep all new fields optional or defaulted for older JSON.

### 2. Update Build Export

Change:

```swift
public static func buildExport(_ context: ModelContext) throws -> CadenceExport
```

To:

```swift
public static func buildExport(
    _ context: ModelContext,
    coachPreferences: ExportCoachPreferences? = nil
) throws -> CadenceExport
```

Update existing tests that call it without preferences. Default preserves compatibility.

### 3. Update ExportView

In `ExportView`:

- Add `@Environment(AppSettings.self) private var settings`.
- Pass `settings.coachPreferenceProfile.exportDTO`.
- Footer copy should mention preferences:
  - `Includes workout history, cardio history, and Coach preferences learned from alternatives you selected.`

### 4. CSV Decision

Preferred for first implementation:

- JSON is the complete portable export.
- CSV remains workout-set oriented.
- Add a short footer in Export explaining JSON includes Coach preferences.

If CSV must include preferences later, add a separate generated section with `coach_preference_type,...` rows. Do not mix preference rows into the set table unless a proper multi-table CSV format is chosen.

## UI Test Seed Plan

Update `Cadence/Cadence/App/UITestSeed.swift` with:

### `coachWhyMixedHistory`

Data:

- One completed strength session this week.
- One completed cardio session this week worth 18 moderate-equivalent minutes.
- Ensure Coach selects an aerobic option because aerobic target is behind.

Assertions:

- Last Cardio appears in Why This Today.
- Strength days and moderate-equivalent rows appear without ticking timers.

### `coachAerobicGap`

Data:

- Strength floor is met.
- Aerobic minutes are behind.
- No lower-body recovery collision.

Assertions:

- Coach's Pick shows moderate aerobic.
- Alternatives include run, walk, cycle, swim/row where launchable.

### `coachCyclePreference`

Data:

- Same as `coachAerobicGap`.
- Seed UserDefaults with a Coach preference profile that favors cycle for `.moderateAerobic`.

Assertions:

- Coach's Pick is cycle, not run, assuming both are eligible.

### `coachLowerBodyRecovery`

Data:

- Recent hard lower-body strength.
- Aerobic target behind.

Assertions:

- Hard/moderate run is not primary.
- Low-impact or easy options appear as closest eligible alternatives.

## Test Plan

### Core Unit Tests

Add or update `CadenceCore/Tests/CadenceCoreTests/CoachDecisionEngineTests.swift`:

- `testObservedFactsIncludeLastCardio`
- `testObservedFactsUseStaticSummaryValues`
- `testObservedFactsPickNewestCardioWhenEventsUnsorted`
- `testNoEvidenceDuplicationDataNeededForInlineSources`
- `testModerateAerobicAlternativesIncludeRunWalkCycleSwimOrRow`
- `testPreferenceForCyclingReordersEligibleModerateAerobicCandidates`
- `testPreferenceDoesNotOverrideRecoveryEligibility`
- `testHighImpactAvoidanceKeepsRunOutOfPrimaryWhenLowImpactCanFulfillIntent`

Add `CoachPreferenceProfileTests.swift`:

- `testRecordAerobicSelectionIncrementsPreference`
- `testRecentRepeatedSelectionOutranksOlderSelection`
- `testStrengthPreferenceIsScopedToMovementPattern`
- `testProfileCodableRoundTrip`

Add or update `DataExportTests.swift`:

- `testJSONExportIncludesCoachPreferences`
- `testJSONExportDecodesWhenCoachPreferencesMissing`
- `testCoachPreferenceExportRoundTrips`

### UI Tests

Create:

- `Cadence/CadenceUITests/WhyThisTodayUITests.swift`

Tests:

- `testWhyTodayShowsLastCardioAndNoTickingWeeklyTimers`
  - Launch with `coachWhyMixedHistory`.
  - Open `coach.card.whyToday`.
  - Assert `whyToday.fact.lastCardio`.
  - Capture label for `whyToday.fact.moderateEquivalentMinutes`.
  - Wait 2 seconds.
  - Assert label unchanged.

- `testWhyTodayShowsCoachPickBeforeRuledOut`
  - Launch with `coachAerobicGap`.
  - Open Why This Today.
  - Assert `whyToday.coachPick`.
  - Assert it appears before `What Coach ruled out` if order can be tested reliably.

- `testWhyTodayDoesNotShowDuplicateEvidenceSection`
  - Assert no static text `Evidence` on Why This Today when inline citations are present.

- `testAlternativesListAndPreferenceSelection`
  - Launch with `coachAerobicGap`.
  - Open Why This Today.
  - Tap `whyToday.coachPick.alternatives`.
  - Choose cycle.
  - Return Home / recompute.
  - Assert Coach's Pick title contains `cycle`.

- `testExportIncludesCoachPreferences`
  - Launch with `coachCyclePreference`.
  - Settings -> Data -> Export.
  - Assert JSON preview contains `coachPreferences` and `cycle`.

### Manual QA

Run these scenarios on simulator and, when HealthKit is involved, on device:

1. No history: Coach shows starter strength, Why Today has no fake Last Cardio.
2. Strength only: Last Strength appears, Last Cardio omitted.
3. Cardio only: Last Cardio appears, Strength days `0 / 2+`.
4. Mixed history: both Last Strength and Last Cardio appear.
5. Learned cycling preference: moderate aerobic Coach's Pick becomes cycling.
6. Lower-body recovery: hard/moderate run is not offered as primary immediately after hard lower-body strength.
7. Export: JSON visibly includes Coach preferences.

## Verification Commands

Run:

```sh
cd CadenceCore && swift test
```

Build:

```sh
xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Focused UI tests:

```sh
xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CadenceUITests/WhyThisTodayUITests -parallel-testing-enabled NO test
```

If the local simulator name differs, use an available iPhone simulator and keep parallel testing disabled.

## Acceptance Criteria

- `What you did` includes Last Cardio when a completed cardio event exists.
- Weekly summary facts do not show live second-by-second timers.
- `Evidence` is not duplicated when inline `The science >` links already cite the claims.
- `COACH'S PICK` is directly below `What you did`.
- `COACH'S PICK` displays the exercise/session prescription clearly.
- `alternatives >` opens a list of eligible full or closest-match alternatives.
- Selecting an alternative stores a preference.
- The next Coach decision uses the stored preference when that option is eligible.
- Preferences do not bypass recovery, pain, active-workout, or lower-body collision gates.
- JSON export includes learned Coach preferences.
- Old JSON exports without Coach preferences still import/decode.

## Suggested Implementation Order

1. Fix `ObservedFact` and `What you did` rendering.
2. Remove duplicate `Evidence` section.
3. Add `COACH'S PICK` section.
4. Add expanded alternatives candidates and alternatives view.
5. Add `CoachPreferenceProfile` and preference-aware scoring.
6. Wire preference recording from alternatives selection.
7. Add export DTOs and `ExportView` integration.
8. Add deterministic UI seeds.
9. Add unit tests and focused UI tests.
10. Run verification commands and update this plan with any deviations.

