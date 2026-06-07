# §01 — Navigation & Action-Oriented Home

> Addresses field notes **#1 (kill the bottom tab bar)** and **#2 (home is
> actions, not a data dashboard)**. This is the foundation the rest of the
> redesign hangs off — it defines the app shell and the front door.

---

## Problem (from the field test)

- The five-tab bar (`Today · Train · Cardio · Trends · Settings`) "takes space and
  isn't useful." On a phone at the gym, a persistent tab bar costs ~49pt of the
  most valuable screen real estate and splits one mental model ("work out") across
  three tabs (Train / Cardio + the type-specific flows).
- The Home screen (`TodayView`) currently re-renders **steps ring, flights /
  distance / energy tiles, a 7-day step chart, and recent workouts** — i.e. a
  read-only mirror of what Apple Health already shows. At the moment the user
  opens the app, they want to *do* something, not read stats.

## What the code does today

- `Cadence/Cadence/App/RootTabView.swift` — `TabView` with 5 `tabItem`s, each
  with an `accessibilityIdentifier` (`tab.today`, `tab.train`, …). This is the
  root view mounted by the app entry point.
- `Cadence/Cadence/Features/Today/TodayView.swift` — `NavigationStack` →
  `ScrollView` of `StepRing`, `activityTiles`, `trendChart`, `recentWorkouts`;
  loads `model.health.todayActivity()` + `activityTrend(7)`.
- Tabs map to: `TodayView`, `TrainView`, `CardioView`, `TrendsView`,
  `SettingsView`.

## Research signal (why action-first is right)

Competitive/UX scan of 2026 strength apps (Hevy, Strong, Fitbod) and fitness-UX
guidance converges on:
- **Minimize taps from open → workout started** ("one decision per screen", bold
  primary CTA like *Start Workout*).
- **Declutter navigation** to a few essentials; don't make the home a dense
  dashboard the user must parse before acting.
- Strong/Hevy specifically win on *fast logging* and a *clean* front door, not on
  a stats wall. Stats live in a dedicated, separately-navigated area.

Conclusion: replace the dashboard home with a **launchpad**, and replace the tab
bar with **in-flow navigation**.

Sources:
- https://www.findyouredge.app/news/best-strength-training-apps-2026
- https://stormotion.io/blog/fitness-app-ux/
- https://easternpeak.com/blog/fitness-app-design-best-practices/

---

## Design

### New app shell (replaces `RootTabView`)

A single root `NavigationStack` whose root is the new **`HomeView`** (the
launchpad). No `TabView`. Everything else is reached by **push** (full screens
like Stats/History) or **sheet/full-screen cover** (the active workout flow).

```
RootView (NavigationStack)
└── HomeView  ........................ the launchpad (root)
     ├─(primary CTA)→ Start Workout  → type picker (§02) → per-type screen
     ├─(secondary)  → Stats          → push: StatsHome (Trends + History + PRs)
     ├─(secondary)  → History        → push: workout history list (was Train list)
     └─(top-bar ⚙)  → Settings       → push: SettingsView
```

- The big win for note #1: with no tab bar, in-workout screens (§04/05/06) get
  the **full height**, which is exactly where the low-vision, far-distance
  legibility requirement lives.
- The old tab destinations are **not deleted** — they're *re-homed* as pushed
  destinations so no functionality is lost (note #1: "we will use other paths to
  access the content"):
  - `TrendsView` + `ExerciseTrendView` → live under **Stats**.
  - `TrainView`'s history list → becomes **History** (the New-Workout button
    moves to Home; see §04 for the screen itself).
  - `CardioView` history merges into **History/Stats** (cardio + strength in one
    timeline). Recording moves under Start Workout (§05).
  - `SettingsView` → gear button, top-trailing on Home.

### `HomeView` content (the launchpad)

Not a dashboard. A short, thumb-reachable stack of **action cards**, biggest at
the bottom (reachable zone) — primary action dominant, secondary actions smaller.

```
┌──────────────────────────────┐
│ Cadence                   ⚙  │   ← large title; gear → Settings
│                              │
│  ┌────────────────────────┐  │
│  │   ▶  START WORKOUT     │  │   ← primary CTA, full-width, tall (≥64pt),
│  │   pick a type →         │  │     high-contrast tint, AX-friendly
│  └────────────────────────┘  │
│                              │
│  (if a session is active)    │
│  ┌────────────────────────┐  │
│  │ ● Resume: Push Day      │  │   ← only shown when a workout is in progress
│  │   12 sets · 00:34:12    │  │     (ties to session engine §02)
│  └────────────────────────┘  │
│                              │
│  ┌──────────┐  ┌──────────┐  │
│  │  📈      │  │  🗓       │  │   ← secondary action cards, 2-up grid
│  │  Stats   │  │ History  │  │
│  └──────────┘  └──────────┘  │
│                              │
│  Last workout: Push Day      │   ← ONE lightweight contextual line, tappable,
│  3 days ago · tap to reuse → │     not a stats panel (feeds §04 "reuse")
└──────────────────────────────┘
```

Design rules:
- **Steps / flights / energy / 7-day chart are removed from Home.** They migrate
  into Stats (still available; see note below). Home shows at most ONE contextual
  nudge ("last workout / reuse"), because it doubles as an action ("reuse").
- **Resume card** appears only when the session engine (§02) reports an active or
  recently-backgrounded session — supports the "continue after a phone call" and
  "don't lose a backgrounded workout" requirement (#4).
- Primary CTA placed low and large for one-handed reach and low-vision tapping
  (≥64pt height, ≥44pt is the floor per NFR-2).

### Where do the old steps stats go?

The tester's point is that Home shouldn't *duplicate* Apple Health — but the data
isn't worthless. Move it into **Stats** as a "Today / Activity" section so it's
one tap away, not the front door. (Open question in §00 §5: keep steps in-app at
all, or link out to Apple Health? Proposed: keep a compact version in Stats;
confirm.)

### Navigation identifiers (keep tests stable)

UI tests currently drive `tab.today`, `tab.train`, etc. Replacing the shell will
break `RootTabView`-based navigation in the UITest suite. Plan:
- New identifiers: `home.startWorkout`, `home.resume`, `home.stats`,
  `home.history`, `home.settings`, `home.reuseLast`.
- Update `Cadence/Cadence/App/UITestSeed.swift` deep-link hooks if present, and
  the navigation steps in `CadenceUITests/*` helpers (`UITestHelpers.swift`) so
  the FR1–FR6 suites navigate via Home instead of tabs. This is mechanical but
  must land in the same change to keep the suite green (CLAUDE.md: verify before
  done).

---

## Data-model deltas

**None for this section.** Pure view/navigation refactor. (The "active session"
state the Resume card needs is defined in §02.)

---

## Implementation steps

1. **Add `HomeView`** (`Features/Home/HomeView.swift`): action cards, gear button,
   conditional Resume card (wired to §02 lifecycle), reuse-last line.
2. **Replace the shell:** swap `RootTabView` for a `RootView` hosting one
   `NavigationStack` rooted at `HomeView`. Keep `RootTabView.swift` only if
   something else references it; otherwise delete and update the app entry point
   (`CadenceApp.swift`).
3. **Re-home destinations:**
   - `StatsHomeView` (new thin wrapper) → embeds `TrendsView` content + a
     compact "Today/Activity" section (migrated from `TodayView`) + PRs.
   - `HistoryView` → the session list extracted from `TrainView` (the New-Workout
     button leaves; it now lives on Home → Start Workout).
   - `SettingsView` reached from the gear.
4. **Retire `TodayView` as a tab** — salvage its `StepRing`/tiles/chart into the
   Stats "Activity" section; delete the tab.
5. **Update UI tests + identifiers** (see above); run the full suite on iPhone +
   iPad.

## Testing

- **Unit:** none (no core logic changes).
- **UI (iPhone + iPad):**
  - Launch → assert `home.startWorkout` exists and is the primary control; assert
    **no tab bar** (e.g. `app.tabBars.count == 0`).
  - From Home, navigate to Stats, History, Settings via the new identifiers;
    assert each destination loads.
  - Resume card hidden when no active session; appears after starting one
    (cross-checks with §02 once that lands).
  - Re-point the existing FR1–FR6 navigation through Home; full suite green.
- **Accessibility:** VoiceOver labels on every card; Dynamic Type at AX5 doesn't
  clip the CTA; contrast check on the primary button (NFR-2).

## Open questions (section-local)

- **Discoverability without a tab bar:** are 2 secondary cards (Stats, History) +
  gear enough, or do we want a small "more" affordance? Proposed: cards are
  enough for v1; revisit if testers get lost.
- **Keep steps in-app at all?** (Cross-listed in §00 §5.) Proposed: compact
  Activity block inside Stats; not on Home.
- **Resume vs. always-new:** if a session is active and the user taps Start
  Workout (not Resume), do we warn/replace or allow parallel sessions? Proposed:
  one active session at a time; Start Workout offers "resume or start new" if one
  is live. (Finalized in §02.)
