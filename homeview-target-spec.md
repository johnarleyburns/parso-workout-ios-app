# HomeView — exact target spec & fixes

Scope: the Home (Today) screen only. Two files:
`Cadence/Cadence/Features/Home/HomeView.swift` and
`Cadence/Cadence/Features/Coach/CoachCardView.swift` (the Coach card is rendered
by Home; three of the five issues live there). Do **not** touch the engine,
repository, models, or any other screen.

Match the mockup exactly. Every contested element below is called out with the
precise SwiftUI. Where it says "leave as-is," do not modify it.

## The five reported gaps → where each is fixed

1. Date is missing next to "Today" → **§1** (HomeView header).
2. Eyebrow says "COACH", should be "COACH · TODAY" → **§2.1**.
3. "The science" is in the wrong place (currently above the Start button) → it
   must sit in the card **footer row, below the green Start button** → **§2.4**.
4. Coach card border is wrong → exact fill + stroke + radius → **§2.5**.
5. "Missing: …" body-parts line shows under "This week" → **remove it** → **§3**.

---

## §1 · HomeView header — date under the large "Today" title

Keep the existing `NavigationStack`, the `.toolbar` settings gear, and the
`ScrollView`. Change the title to "Today" and add the date as the **first item**
inside the content `VStack`, directly beneath the large title.

`.navigationTitle`:

```swift
            .navigationTitle("Today")
```

Add a date string helper to `HomeView` (deterministic "Saturday, Jun 21"):

```swift
    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")   // locale-aware "Saturday, Jun 21"
        return f
    }()
    private var headerDateText: String { Self.headerDateFormatter.string(from: .now) }
```

Make the date the first child of the content `VStack` (it renders just under the
large nav title and scrolls away with it — standard iOS behavior):

```swift
                VStack(alignment: .leading, spacing: 20) {
                    Text(headerDateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("home.headerDate")

                    if let s = active.strengthSession { resumeCard(s) }
                    CoachCardView(recommendation: coachRecommendation,
                                  insightCount: coachInsights.count,
                                  unit: settings.unit,
                                  onStart: { launchPrescription(coachRecommendation) },
                                  onSeeAll: { path.append(HomeRoute.coach) })
                    quickActionsRow
                    thisWeekCard
                    favoritesSection
                    recentWorkoutsSection
                }
                .padding()
```

The settings gear stays exactly as it is (top-trailing toolbar item). Do not add
a second gear in the content.

`quickActionsRow`, `favoritesSection`, `recentWorkoutsSection`, and the
`launchPrescription` / routing helpers are unchanged.

---

## §2 · CoachCardView — full corrected card

Replace the entire `CoachCardView` struct with the following. The element order
is the contract: **eyebrow → recommendation → target chip → green Start →
science/insights footer row → (expanded science) → disclaimer.** "The science"
is now a footer toggle *below* the Start button, not inside the recommendation
block.

```swift
struct CoachCardView: View {
    let recommendation: Recommendation
    var insightCount: Int
    var unit: MeasurementUnitPreference
    var onStart: () -> Void
    var onSeeAll: () -> Void

    @State private var scienceExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1 — eyebrow: "COACH · TODAY" + About (info) link
            HStack(spacing: 8) {
                Image(systemName: "figure.mind.and.body").font(.caption)
                Text("COACH · TODAY").font(.caption.bold()).tracking(1.2)
                Spacer()
                NavigationLink { CoachAboutView() } label: {
                    Image(systemName: "info.circle").font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach.card.about")
                .accessibilityLabel("About the Coach")
            }
            .foregroundStyle(.tint)

            // 2 — recommendation title, action, and the loggable target chip.
            //     showScience: false suppresses this component's own toggle so
            //     "The science" can live in the footer (item 4) instead.
            RecommendationContentView(recommendation: recommendation,
                                      unit: unit,
                                      headline: true,
                                      showScience: false)

            // 3 — the one primary action
            Button { Haptics.selection(); onStart() } label: {
                Label("Start workout", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(.green, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.coachStart")
            .accessibilityLabel("Start the coach's workout")

            // 4 — footer row: "The science" (left) · "All insights (n)" (right)
            HStack(spacing: 12) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { scienceExpanded.toggle() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "book.closed")
                        Text("The science")
                        Image(systemName: scienceExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach.card.why")
                .accessibilityLabel(scienceExpanded ? "Hide the science" : "Why — show the science")

                Spacer()

                if insightCount > 0 {
                    Button { Haptics.selection(); onSeeAll() } label: {
                        HStack(spacing: 4) {
                            Text("All insights (\(insightCount))")
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach.card.seeAll")
                }
            }

            // 5 — expanded science: detail + citations, revealed under the footer
            if scienceExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recommendation.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(recommendation.allCitations) { c in
                        CitationLink(citation: c)
                    }
                }
                .transition(.opacity)
            }

            // 6 — disclaimer (last line, tiny)
            Text("Coaching, not medical advice.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.tint.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card")
    }
}
```

### §2.1 Eyebrow
Text is `"COACH · TODAY"` (middle dot `·`, U+00B7), `.font(.caption.bold())`,
`.tracking(1.2)`, tint-colored (the whole eyebrow `HStack` is
`.foregroundStyle(.tint)`). The leading `figure.mind.and.body` glyph and the
trailing `info.circle` About link stay.

### §2.2 Recommendation block
Rendered by `RecommendationContentView(..., showScience: false)` — see §2.6 for
the one-line change that adds that parameter. This gives you the title
("Add weight to Squat"), the action subtitle, and the target chip
("3 × 5 · 145 lb · RIR 2" with the confidence label). **Leave the target chip's
own styling as-is** — it is not one of the reported issues.

### §2.3 Start button
Green filled, full width, `play.fill` + "Start workout",
`RoundedRectangle(cornerRadius: 13)`, white text. Reuses the
`home.coachStart` accessibility id so existing tests keep finding it.

### §2.4 Science / insights footer row — THE placement fix
This `HStack` sits **after** the Start button. Left: "The science" disclosure
toggle (secondary, with a chevron that flips up when open). Right (only when
`insightCount > 0`): "All insights (n) ›" in tint. When the toggle is open, the
detail + citations appear in item 5, directly below this row — never above the
Start button.

### §2.5 Card border — exact values
```swift
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.tint.opacity(0.25), lineWidth: 1))
```
Corner radius `20`, fill `.tint.opacity(0.10)`, single `1`-pt stroke at
`.tint.opacity(0.25)`. No second border, no material, no shadow. Both shapes use
the same `cornerRadius: 20` so the stroke hugs the fill.

### §2.6 RecommendationContentView — add the `showScience` flag
This is the only change to `RecommendationContentView`. Add the stored property,
then wrap its existing "Why / the science" button **and** its existing expanded
`if expanded { … }` block in `if showScience { … }`. Everything else in that view
is untouched.

```swift
struct RecommendationContentView: View {
    let recommendation: Recommendation
    var unit: MeasurementUnitPreference
    var headline: Bool = false
    var showScience: Bool = true        // NEW — default true keeps every other caller identical
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ... title + action + target chip stay exactly as they are ...

            if showScience {
                // the existing "coach.card.why" Button …
                // … and the existing `if expanded { detail + citations }` block
            }
        }
    }
}
```

Because the default is `true`, the full insights list (the other place this view
is used) is unaffected — only the Home card passes `showScience: false`.

---

## §3 · HomeView "This week" card — drop the "Missing: …" line

The card is header + four metrics, nothing else. Delete the
`if !coverage.missing.isEmpty { Text("Missing: …") }` block entirely. (The missing
body-parts detail still lives on the Details screen via the header's "Details ›".)

```swift
    private var thisWeekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                Button { Haptics.selection(); path.append(HomeRoute.coach) } label: {
                    HStack(spacing: 3) {
                        Text("Details").font(.caption)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                weekMetric("\(workoutsThisWeek)", "workouts", id: "home.workoutsCount")
                weekMetric("\(cardioMinutesThisWeek)m", "cardio", id: "home.cardioMinutes")
                weekMetric(compactVolume(), "volume", id: "home.volume")
                weekMetric("\(bodyPartsThisWeek.hit.count)/\(BodyPart.allCases.count)",
                           "parts", id: "home.bodyParts")
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("home.thisWeek")
    }

    private func weekMetric(_ value: String, _ label: String, id: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.bold()).monospacedDigit()
                .minimumScaleFactor(0.5).lineLimit(1)
                .accessibilityIdentifier(id)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Compact weekly volume for the calm 4-across row (e.g. "12.4k"); the unit
    /// is implied by Settings and shown in full on the Details screen.
    private func compactVolume() -> String {
        let value = settings.unit == .pounds ? volumeThisWeekKg * 2.2046226 : volumeThisWeekKg
        if value >= 1000 { return String(format: "%.1fk", value / 1000) }
        return String(format: "%.0f", value)
    }
```

Labels are the short forms shown in the mockup: `workouts`, `cardio`, `volume`,
`parts`. If you would rather keep the full `Format.weight(...)` string for volume,
that is fine — but keep `minimumScaleFactor(0.5)` so four metrics never overflow
one row.

---

## Definition of done

- [ ] Large title reads "Today"; the current date sits directly beneath it
      (`home.headerDate`), e.g. "Saturday, Jun 21".
- [ ] Coach eyebrow reads exactly "COACH · TODAY", tint-colored, with the About
      (info) link still top-right.
- [ ] Card order top-to-bottom: eyebrow, title, action, target chip, green
      "Start workout", then the "The science / All insights (n)" footer row.
- [ ] "The science" toggle is **below** the Start button. Opening it reveals the
      detail + citations beneath the footer row — nothing moves above the button.
- [ ] Coach card: radius 20, fill `.tint.opacity(0.10)`, single 1-pt
      `.tint.opacity(0.25)` stroke.
- [ ] "This week" shows only the header + four metrics. No "Missing: …" line.
- [ ] `swift test` in `CadenceCore` still green (untouched); app builds; existing
      `coach.card`, `coach.card.why`, `coach.card.target`, `home.coachStart` ids
      still resolve.
```