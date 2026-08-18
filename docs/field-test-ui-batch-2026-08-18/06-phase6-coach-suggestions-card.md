# Phase 6 — Coach's Suggestions card: floating icon, trimmed copy, bottom CTA

Field-test issues #8, #9, #11:

- *"make the 'coach icon' all the way to the top right of the bounding box (with
  small margin) and make the icon 'float' over the rest of the box instead of
  taking up its own layout space"*
- *"remove the Coach's Suggestions horizontal bar above Suggested Workout, and
  remove the whole text blurb of 'Suggested Workout + subtitle' as it's
  unnecessary I can infer that from the workout below"*
- *"move the suggested workout to the bottom and BELOW the coach's suggestions
  bounding box have a button Do Coach's Workout and make it full width and height
  and spacing matching exactly the top home view Start Workout button"*

Depends on **Phase 1** (button metrics) and **Phase 5** (`CoachSourcesLink`).

## 1. What the code does today

`Home/HomeView.swift:636-691` `coachSuggestionsSection`:

```
VStack(spacing: 10) {
    HStack(top) { Text("Coach’s Suggestions").headline; Spacer;
                  HomeCoachIllustrationView(compact: true) }   ← 88×88, takes layout space
    HomeCoachRecommendationCard(...)                           ← FIRST, not last
    ForEach(visibleSuggestions) { … }
    Show more…/Show less
}
.padding().cadenceGlassCard(corner 16, tint: .purple)
.accessibilityIdentifier("coach.card")
```

`Home/HomeCoachRecommendationCard.swift`:
```
Divider().padding(.top, 2)                       ← the "horizontal bar" to remove
Text("Suggested Workout")                        ← blurb to remove
Text("Selected for today based on …")            ← subtitle to remove
Text(recommendation.title)                       ← keep
Text("Why this workout") + subtitle              ← keep
previewDetails (exercise list)                   ← keep
ForEach(citations) { CitationLink }              ← becomes CoachSourcesLink (P5)
Button("Do Coach's Workout")                     ← moves OUTSIDE the card
```

## 2. Target layout

```
        ┌───────────────────────────────────────────┐
        │ Coach’s Suggestions              ┌──────┐ │  ← icon overlays the card's
        │                                  │ 🏋️  │ │    top-right corner, 12 pt
        │ ● Volume is on track             └──────┘ │    inset, zero layout cost
        │   You hit 14 sets for legs this week.     │
        │   The science ›                           │
        │                                           │
        │ ● Chest is below its starting range       │
        │   …                                       │
        │   The science ›                           │
        │                                           │
        │ Show more…                                │
        │                                           │
        │ ─────────────────────────────────────────  │
        │ Upper body — push emphasis                │  ← the suggested workout,
        │ Why this workout                          │    now at the BOTTOM,
        │ It closes this week's chest deficit.      │    inside the card
        │ 🏋️ Bench Press                    45 kg   │
        │ 🏋️ Overhead Press                 30 kg   │
        │ 🏋️ Triceps Pushdown               25 kg   │
        │ The science ›                             │
        └───────────────────────────────────────────┘
                          ↕ 12 pt (actionButtonSpacing)
        ┌───────────────────────────────────────────┐
        │  ▶  Do Coach's Workout                    │  ← OUTSIDE the card,
        └───────────────────────────────────────────┘    56 pt, identical to
                                                          Home's Start Workout
```

Notes:
- The heading `Coach’s Suggestions` stays (it is the card's title; the user asked
  to remove the *divider bar above Suggested Workout*, not the card heading).
- The illustration becomes `.overlay(alignment: .topTrailing)` on the card, with
  `.padding(12)` and `.allowsHitTesting(false)`. Shrink it from 88 → **64 pt** so
  it does not collide with the heading text at large Dynamic Type; add
  `.accessibilityHidden(true)` (it is decorative; the label already exists but a
  floating decorative image should not be a VoiceOver stop).
- The suggestion list keeps its existing collapsed/expand behaviour and tone
  colours untouched.
- A single `Divider()` separates the suggestion list from the suggested workout —
  that is a *different* divider from the removed one and is needed now that the
  workout sits at the bottom. If the suggestion list is empty, omit it.

## 3. Extraction (mandatory)

`Home/HomeView.swift` is **exactly at its 1115 LOC ratchet ceiling** and cannot
grow by one line. Move the whole section out:

**New — `Cadence/Cadence/Features/Home/HomeCoachSuggestionsSection.swift`**

```swift
struct HomeCoachSuggestionsSection: View {
    let suggestions: [HomeSuggestion]
    let recommendation: CoachSession?
    let illustration: HomeCoachIllustration
    @Binding var expanded: Bool
    let onStartRecommendation: () -> Void
}
```
- Owns the card, the floating illustration overlay, the suggestion rows, the
  Show more/less control, the trailing suggested-workout block, and the external
  `Do Coach's Workout` button (the whole thing returns a
  `VStack(spacing: LayoutMetrics.actionButtonSpacing)` of [card, button]).
- `HomeView` keeps only:
  ```swift
  HomeCoachSuggestionsSection(
      suggestions: dashboard.suggestions,
      recommendation: previewableCoachRecommendation,
      illustration: coachIllustration,
      expanded: $suggestionsExpanded,
      onStartRecommendation: { launchDecision(...) })
  ```
- `suggestionTint(_:)` moves into the new file (or, better, into the presenter as
  a semantic enum — see §4).
- After the move, **lower HomeView's ratchet entry** in
  `scripts/check-test-pyramid.sh` to the new LOC.

`HomeCoachRecommendationCard.swift` is rewritten to be the *body only* (title,
"Why this workout", preview details, science link) — no divider, no
"Suggested Workout" heading/subtitle, no button.

## 4. Presenter — new `CadenceCore/Sources/CadenceFeatures/HomeCoachSectionPresenter.swift`

Keeps the ordering/visibility rules testable (guard rule 2).

```swift
public enum HomeCoachSectionPresenter {

    /// The card's blocks, in render order. The suggested workout is always last
    /// (field test 2026-08-18 #11).
    public enum Block: Equatable {
        case heading                       // "Coach’s Suggestions"
        case suggestion(HomeSuggestion)
        case showMore(expanded: Bool)
        case divider
        case suggestedWorkout(title: String, why: String, exercises: [ExercisePreview])
    }

    public struct ExercisePreview: Equatable {
        public let name: String
        public let loadKg: Double?
        public let sets: Int?
        public let repsText: String?
    }

    /// Tone → a semantic colour role the view maps (no SwiftUI in this module).
    public enum ToneRole: Equatable { case positive, warning, neutral }
    public static func toneRole(_ tone: HomeSuggestion.Tone) -> ToneRole

    public static func blocks(suggestions: [HomeSuggestion],
                              recommendation: CoachSession?,
                              expanded: Bool) -> [Block]

    /// Whether the external "Do Coach's Workout" button renders.
    public static func showsPrimaryAction(recommendation: CoachSession?) -> Bool

    /// Max 6 exercises + an "+N more" affordance, matching today's preview.
    public static func previewExercises(_ session: CoachSession) -> [ExercisePreview]
    public static func additionalExerciseCount(_ session: CoachSession) -> Int
}
```

The existing `HomeDashboardPresenter.visibleSuggestions(_:expanded:)` stays and is
called from `blocks(...)`.

## 5. Identifiers

Keep (smoke test + existing assertions depend on them):
`coach.card`, `home.coachRecommendation`, `home.coachRecommendation.start`,
`home.suggestions.showMore`, `home.suggestions.showLess`,
`home.suggestion.<id>.science`, `home.suggestedWorkout.title`,
`home.coachIllustration`.

New: `home.coachSuggestions.card` on the glass card itself (so the button, which
is now a sibling, is not swallowed by `coach.card`'s bounds).

Must **not** exist afterwards: `home.coachRecommendation.preview` (already gone —
the smoke test asserts its absence; keep that assertion passing).

## 6. Tests

### New — `CadenceCore/Tests/CadenceFeaturesTests/HomeCoachSectionPresenterTests.swift`
```
testSuggestedWorkoutIsAlwaysTheLastBlock
testHeadingIsAlwaysFirst
testShowMoreOnlyAppearsWithMoreThanOneSuggestion
testCollapsedShowsOnlyTheFirstSuggestion
testExpandedShowsEverySuggestion
testDividerOnlyAppearsBetweenSuggestionsAndTheWorkout
testNoDividerWhenThereAreNoSuggestions
testNoSuggestedWorkoutBlockForRecoveryOrRestRecommendations
testShowsPrimaryActionOnlyWhenARecommendationIsLaunchable
testPreviewExercisesCapAtSixWithAdditionalCount
testToneRoleMapsPositiveWarningNeutral
```

### `CadenceCore/Tests/CadenceFeaturesTests/HomeDashboardPresenterTests.swift`
Re-run unchanged; `visibleSuggestions` behaviour must not regress.

### UI smoke — inside the single existing test, replacing/extending the current
coach-card block:
```swift
XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10),
              "Coach card did not render on Home")
XCTAssertFalse(app.staticTexts["Suggested Workout"].exists,
               "Coach card still shows the removed Suggested Workout blurb")
if app.descendants(matching: .any)["home.coachRecommendation"].exists {
    XCTAssertTrue(app.buttons["home.coachRecommendation.start"].exists,
                  "Do Coach's Workout is missing below the coach card")
    XCTAssertEqual(app.buttons["home.coachRecommendation.start"].frame.height,
                   app.buttons["home.startWorkout"].frame.height, accuracy: 1,
                   "Do Coach's Workout does not match Home Start Workout's height")
    XCTAssertGreaterThan(app.buttons["home.coachRecommendation.start"].frame.minY,
                         app.descendants(matching: .any)["home.coachSuggestions.card"].frame.minY,
                         "Do Coach's Workout is not below the Coach's Suggestions card")
}
XCTAssertFalse(app.buttons["home.coachRecommendation.preview"].exists,
               "Coach card still exposes the removed Preview Workout action")
```

## 7. Acceptance criteria

- [ ] The coach illustration sits at the card's top-right, overlapping the card's
      content, with a ~12 pt inset and **no** reserved layout space (the heading
      row is full-width again).
- [ ] The `Divider()` above the suggested workout block inside
      `HomeCoachRecommendationCard` is gone.
- [ ] The `Suggested Workout` heading and its
      "Selected for today based on…" subtitle are gone.
- [ ] The suggested workout renders **after** the suggestion list and after
      Show more/less.
- [ ] `Do Coach's Workout` is a full-width 56 pt button **outside and below** the
      Coach's Suggestions card, 12 pt beneath it, visually identical to Home's
      `Start Workout`.
- [ ] Each suggestion still shows at most one `The science ›` row (P5).
- [ ] `HomeView.swift` shrank; the ratchet entry in
      `scripts/check-test-pyramid.sh` was lowered to its new LOC.
- [ ] `HomeCoachSuggestionsSection.swift` and `HomeCoachRecommendationCard.swift`
      each ≤ 400 LOC.
- [ ] `make ci` green; `make smoke` green.

## 8. Commit

```
feat: restructure Coach's Suggestions — floating icon, workout last, CTA below

Field test 2026-08-18 #8/#9/#11. The coach artwork floats over the card's
top-right corner, the redundant Suggested Workout blurb and its divider are gone,
the suggested workout moves to the bottom of the card, and Do Coach's Workout
becomes a full-width action below the card matching Home's Start Workout.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

Update `current_status.md`, commit, **do not push**, report, stop.
