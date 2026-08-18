# Phase 5 — One "The science ›" row, many sources on the Source screen

Field-test issue #10: *"On Coach's Suggestions (and anywhere else this happens)
DO NOT list multiple 'The science >' rows, but instead only one even if there are
multiple links, and instead when you go to 'Source View' with the scientific
sources, just list multiple vertically on that same view there is plenty of room
and scroll if necessary."*

## 1. What the code does today

`CitationLink` (`Cadence/Cadence/Features/Coach/CoachCardView.swift:92-127`)
renders **one** citation and pushes `CitationDetailView` (title / authors / year /
source / "How this applies" / "Read the paper").

Call sites that render a `ForEach` of them — these are the "multiple The science
rows" the user sees:

| File | Line | Source of ids |
|---|---|---|
| `Home/HomeCoachRecommendationCard.swift` | 27-29 | `recommendation.citationIds` |
| `Coach/CoachDecisionCardView.swift` | 102-104 | `warning.citationIds` |
| `Coach/CoachDecisionCardView.swift` | 138-140 | `structure.citationIds` |
| `Coach/PlannedDayPreviewView.swift` | 66-70 | day/session citation ids |
| `Coach/CoachAlternativesView.swift` | 87-91 | alternative session ids |
| `Coach/CoachMethodologyView.swift` | 333-341 | per-topic study list |
| `Coach/CoachAboutView.swift` | 34-38 | about list |
| `Plan/AssessmentDetailView.swift` | 45-49 | assessment protocol ids |
| `Intervals/IntervalSetupView.swift` | 250-256 | protocol ids |

`CoachMethodologyView` and `CoachAboutView` are **reference/bibliography
screens** whose whole purpose is a list of studies — they are *not* "a coaching
output with several citations". Leave those two alone (see acceptance criteria).
Everything else converts.

## 2. Design

```
Coach card
  …message…
  The science ›                ← exactly one row, however many sources
        │
        ▼
  ┌ Sources ──────────────────────────────┐   scrollable List
  │ Schoenfeld et al. (2021)              │
  │ Dose-response of resistance training… │
  │ Journal of Sports Sciences · 2021     │
  │ How this applies: …                   │
  │ Read the paper ↗                      │
  │ ─────────────────────────────────────  │
  │ Pareja-Blanco et al. (2020)           │
  │ …                                     │
  └───────────────────────────────────────┘
```

- **One** source → the row still says `The science ›` and pushes the same
  `CoachSourcesView`, which then shows one entry. One code path, one look.
  (`CitationLink` stays for the handful of genuinely-single, non-coach call sites
  that already read well: `PRTimelineView`, `ConsistencyHeatmapView`,
  `RPEInfoView`, `ProgressView`, `CoachSchedulePreferencesView`,
  `PassiveReadinessCard`, `CoachPartVolumeSection`, `CoachTestRecommendationCard`,
  `YourWeekView`, `CoachCardView` — none of them render a `ForEach`.)

## 3. Presenter — new `CadenceCore/Sources/CadenceFeatures/CitationPresenter.swift`

```swift
import Foundation
import CadenceCore

/// Resolves a coaching output's citation ids into the ordered, de-duplicated
/// citations a single "The science" link opens. Pure so the HARD RULE ("every
/// coaching output cites navigable science") is unit-tested rather than asserted
/// by eye in a view.
public enum CitationPresenter {

    /// Ordered, de-duplicated citations for the given ids. Unknown ids are
    /// dropped — a raw id must never reach the UI.
    public static func citations(forIds ids: [String]) -> [Citation]

    /// Ids that did not resolve. Non-empty means the registry and the engine
    /// have drifted; `CitationIntegrityTests` fails on it.
    public static func unresolvedIds(_ ids: [String]) -> [String]

    /// Whether a science link should be shown at all.
    public static func hasScience(_ ids: [String]) -> Bool

    /// Screen title: "Source" for one, "Sources" for several.
    public static func sourcesTitle(count: Int) -> String
}
```

## 4. Views

### New — `Cadence/Cadence/Features/Coach/CoachSourcesView.swift`

```swift
struct CoachSourcesView: View {
    let citations: [Citation]
    /// Optional per-citation "How this applies" copy, keyed by citation id.
    var contexts: [String: String] = [:]
}
```
- A `List` (scrolls for free) with one `Section` per citation, each rendering the
  same content `CitationDetailView` shows for a single source: title, authors,
  year + journal, optional context, `Read the paper` link.
- Navigation title = `CitationPresenter.sourcesTitle(count:)`.
- `accessibilityIdentifier("coach.sources")`; each section
  `coach.sources.<citation.id>`; each link `coach.sources.<id>.link`.
- Refactor `CitationDetailView` so both screens share one
  `CitationDetailBody(citation:context:)` subview rather than duplicating markup.

### New — `CoachSourcesLink` (add to `Coach/CoachCardView.swift`, next to `CitationLink`)

```swift
/// One "The science ›" row for a coaching output that cites any number of
/// studies. Never renders more than one row (field test 2026-08-18 #10).
struct CoachSourcesLink: View {
    let citationIds: [String]
    /// Optional per-id "How this applies" copy.
    var contexts: [String: String] = [:]
    var identifier: String = "coach.sources.link"
}
```
- Renders nothing when `CitationPresenter.hasScience(citationIds) == false`.
- Label is the existing `compactLabel` look: `The science ›`
  (`.font(.caption2)`, `.foregroundStyle(.tint)`).
- `.accessibilityLabel("The science, \(n) source\(n == 1 ? "" : "s")")`.
- `minHeight: 44`, `.contentShape(Rectangle())`.
- `CoachCardView.swift` is 150 LOC — adding this keeps it well under 400.

### Call-site conversions
Replace each `ForEach(… citationIds …) { CitationLink(…) }` with a single
`CoachSourcesLink(citationIds: …)` in:
`HomeCoachRecommendationCard`, `CoachDecisionCardView` (both sites),
`PlannedDayPreviewView`, `CoachAlternativesView`, `AssessmentDetailView`,
`IntervalSetupView`.

Preserve existing identifiers where a test uses them; where the old code had no
id, use `identifier:` to give one (`coach.card.warnings.science`,
`coach.card.structure.science`, `home.coachRecommendation.science`,
`coach.alternatives.<id>.science`, `plan.day.science`, `assessment.science`,
`interval.science`).

`CoachDecisionCardView` is 460/570 LOC — this change shrinks it.

## 5. Tests

### New — `CadenceCore/Tests/CadenceFeaturesTests/CitationPresenterTests.swift`
```
testResolvesKnownIdsInOrder
testDropsUnknownIds
testDeDuplicatesRepeatedIds
testHasScienceIsFalseForEmptyAndForAllUnknownIds
testSourcesTitleIsSingularForOneAndPluralForMany
```

### `CadenceCore/Tests/CadenceCoreTests/CitationIntegrityTests.swift` (extend)
```
testEveryCoachSessionCitationIdResolves
    // for every CoachSession produced by the engines in the existing fixtures,
    // CitationPresenter.unresolvedIds(session.citationIds).isEmpty
testEveryDecisionWarningCitationIdResolves
```
This is the enforcement of the HARD RULE: a science claim referencing a missing
id now fails `swift test`.

### UI smoke — inside the single existing test
```swift
// Field test 2026-08-18 #10: at most one science row per coach output.
let science = app.descendants(matching: .any)
    .matching(NSPredicate(format: "label BEGINSWITH 'The science'"))
XCTAssertLessThanOrEqual(science.count, 3,
    "Coach surfaces render a separate science row per citation again")
```
(3 = one per visible coach output on Home: the card, a suggestion, the
recommendation — the bug produced one per *citation*, typically 6+.)

## 6. Acceptance criteria

- [ ] No coaching-output view contains `ForEach(... CitationLink ...)`.
      Verify: `grep -rn "ForEach" Cadence/Cadence/Features --include=*.swift -A3 | grep CitationLink`
      returns only `CoachMethodologyView.swift` and `CoachAboutView.swift`.
- [ ] `CoachSourcesView` lists every source vertically and scrolls.
- [ ] Each source shows title, authors, year, journal, optional "How this
      applies", and a working `Read the paper` link.
- [ ] Raw citation ids are never displayed.
- [ ] `docs/CITATIONS.md` and `CitationRegistry.all` still agree
      (`CitationIntegrityTests` green).
- [ ] `make ci` green; `make smoke` green.

## 7. Commit

```
feat: one science link per coaching output, all sources on one screen

Field test 2026-08-18 #10. CoachSourcesLink renders a single "The science ›" row
however many studies back the output and pushes CoachSourcesView, which lists
them vertically. CitationPresenter makes the resolution unit-tested.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

Update `current_status.md`, commit, **do not push**, report, stop.
