# Phase 8 — This Week → Coach & Plan settings deep link

Field-test issue #7: *"have a settings gear icon on the top right of the This
Week home view bounding box to 'deep link' to Coach & Plan settings view to make
navigation easier, and make sure to 'back' navigate in this case to the home view
instead of to Settings view."*

Smallest phase. Depends on **Phase 7** only for HomeView LOC headroom.

## 1. What the code does today

- `Home/HomeWeekDashboardSection.swift` renders the card:
  `VStack { Text("This Week").font(.headline); …rows…; Show more/less }`
  with `.padding()` + `.cadenceGlassCard(corner 16, tint: .green)`. There is no
  action in its header.
- The Coach & Plan screen is `Coach/CoachSchedulePreferencesView.swift`, reached
  today only via **Settings → Coach → Coach & Plan**
  (`Settings/SettingsView.swift:166-168`).
- **`HomeRoute.coachPreferences` already exists** (`Home/HomeRouting.swift:33`)
  and `HomeView`'s `navigationDestination(for: HomeRoute.self)` already maps
  `case .coachPreferences: CoachSchedulePreferencesView()`
  (`Home/HomeView.swift:325`).

That last point is the whole answer to "back should go to Home": pushing
`HomeRoute.coachPreferences` onto Home's own `NavigationStack` path means the
back button pops to **Home**, because Settings was never on the stack. No custom
back handling, no `NavigationPath` surgery.

## 2. Design

```
┌─ This Week ──────────────────────────── ⚙︎ ─┐   gear pinned top-right,
│ Strength   ▓▓▓▓▓▓▓░░░   3 / 4 days          │   44×44 hit target,
│ Cardio     ▓▓▓▓░░░░░░  90 / 150 min         │   aligned with the heading
│ Volume     ▓▓▓▓▓▓░░░░   5 / 8 parts         │   baseline
│ Show more…                                  │
└─────────────────────────────────────────────┘
```

Unlike the coach illustration (Phase 6), this gear **is** interactive, so it is a
real element in the header `HStack`, not an overlay — it must be reachable by
VoiceOver and by Full Keyboard Access.

## 3. Implementation

### `Home/HomeWeekDashboardSection.swift`
Add a parameter and a header row:

```swift
let onOpenCoachSettings: () -> Void
…
HStack {
    Text("This Week").font(.headline)
    Spacer()
    Button {
        Haptics.selection()
        onOpenCoachSettings()
    } label: {
        Image(systemName: "gearshape")
            .imageScale(.medium)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .accessibilityIdentifier("home.week.coachSettings")
    .accessibilityLabel("Coach and plan settings")
    .accessibilityHint("Opens Coach & Plan preferences")
}
```
Offset the button by `.padding(.trailing, -8)` / `.padding(.top, -8)` so the
44 pt hit target does not visually inflate the card header — the *glyph* should
sit at the card's inset corner while the *target* stays 44 pt.

The card's existing spacing (`LayoutMetrics.cardRowSpacing`) is unchanged.

### `Home/HomeView.swift`
```swift
HomeWeekDashboardSection(
    …existing arguments…,
    onOpenCoachSettings: { path.append(HomeRoute.coachPreferences) })
```
One line. HomeView grows by one line — it shrank in Phases 6 and 7, so there is
headroom; re-check the ratchet regardless.

### `Coach/CoachSchedulePreferencesView.swift`
**No change needed** — it already sets `.navigationTitle("Coach & Plan")`
(line 256), so the pushed destination is self-identifying from Home and the smoke
test can match on that nav-bar title.

## 4. Tests

### New — `CadenceCore/Tests/CadenceFeaturesTests/HomeRouteTests.swift`
`HomeRoute` lives in the app target, not CadenceFeatures, so it cannot be unit
tested directly. Instead assert the *invariant that matters* where it is
testable: nothing. **Skip this test file** — the deep link is pure navigation
wiring with no logic, and the guard rule says new coverage goes to `swift test`
*when there is logic to cover*. Cover it in the smoke test instead.

### UI smoke — inside the single existing test
Insert after the This Week expand/collapse block:

```swift
// Field test 2026-08-18 #7: the This Week gear deep-links to Coach & Plan and
// backs out to Home, not to Settings.
XCTAssertTrue(app.scrollToHittableAndTap("home.week.coachSettings"),
              "This Week did not offer a Coach & Plan shortcut")
XCTAssertTrue(app.navigationBars["Coach & Plan"].waitForExistence(timeout: 10),
              "This Week gear did not open Coach & Plan")
app.navigationBars.buttons.element(boundBy: 0).tap()
XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 10),
              "Back from Coach & Plan did not return to Home")
XCTAssertFalse(app.navigationBars["Settings"].exists,
               "Back from Coach & Plan landed on Settings instead of Home")
```

## 5. Acceptance criteria

- [ ] A gear glyph sits at the top-right of the This Week card with a 44×44 hit
      target and does not shift the heading or the rows.
- [ ] Tapping it pushes `CoachSchedulePreferencesView` **on Home's stack**.
- [ ] The destination's navigation title reads `Coach & Plan`.
- [ ] Back returns to Home; Settings never appears in the stack.
- [ ] Settings → Coach → Coach & Plan still works unchanged.
- [ ] VoiceOver announces "Coach and plan settings, button".
- [ ] `HomeWeekDashboardSection.swift` ≤ 400 LOC; HomeView within its ratchet.
- [ ] `make ci` green; `make smoke` green.

## 6. Commit

```
feat: deep-link This Week to Coach & Plan preferences

Field test 2026-08-18 #7. A gear in the This Week card header pushes
CoachSchedulePreferencesView onto Home's own navigation stack, so Back returns to
Home rather than to Settings.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

Update `current_status.md`, commit, **do not push**, report, stop.
