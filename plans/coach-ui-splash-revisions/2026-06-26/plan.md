# Coach UI, Your Week Insights, Preferences, And Splash Handoff Plan

Date: 2026-06-26

Status: planning artifact only. Do not treat this file as an implementation.

Working tree note: at planning time, `revisions-plan.md` was already untracked. Do not edit, delete, move, or stage that file unless the user explicitly asks.

## Objective

Implement a focused polish pass that:

1. Restores the old image-backed custom splash experience, but regenerates the image with ImageMagick as grayscale, resized, and center-cropped for the intended iPhone full-screen splash resource size.
2. Removes the `Details >` link from Home's `This week` card.
3. Moves Coach insights into a compact `Coach's Insights` section at the bottom of `Your Week`.
4. Moves the full `My Preferences` controls out of `Why This Today` and hides them behind a compact `Review my preferences >` link.
5. Reconciles the completed-plan Home `COACH` state with the `Why This Today` screen so the latter does not show a contradictory `Coach's Pick` after today's plan has already been followed.

## Non-Goals

- Do not redesign the whole Home screen.
- Do not change the Coach scoring engine unless a test proves the UI-only reconciliation cannot be made correct.
- Do not change the actual iOS generated launch screen settings unless the user separately asks for a pre-SwiftUI launch-screen asset.
- Do not remove or rewrite unrelated Coach science/citation machinery.
- Do not refactor large view files beyond what is needed to make these screens coherent.

## Current State Summary

### Splash

Relevant files:

- `Cadence/Cadence/App/SplashView.swift`
- `Cadence/Cadence/App/RootTabView.swift`
- `Cadence/Cadence/Assets.xcassets/splash.imageset/Contents.json`
- `Cadence/Cadence/Assets.xcassets/splash.imageset/splash.jpg`
- `Cadence/Cadence/Resources/splash.jpg`
- `Cadence/Cadence.xcodeproj/project.pbxproj`

Verified state:

- `SplashView.swift` currently renders a plain `Color(.systemGray6)` background plus centered text.
- The old image-backed splash implementation is visible in git commit `8c5e5f1`.
- The splash image asset still exists.
- Current splash image dimensions are `1280x1920`.
- ImageMagick is installed and `identify` works.
- Xcode project has `INFOPLIST_KEY_UILaunchScreen_Generation = YES`; the app uses Apple's generated launch screen before SwiftUI starts.
- `RootTabView` overlays `SplashView` after onboarding is complete. This is a custom in-app splash, not the real static launch screen.

Important implication:

- The image asset should be treated as the custom SwiftUI splash resource. Do not change `Info.plist`, generated launch-screen build settings, or add a storyboard in this pass.

### Home `This week`

Relevant file:

- `Cadence/Cadence/Features/Home/HomeView.swift`

Verified state:

- `thisWeekCard` contains a `Details >` button in the header.
- That button currently routes to `HomeRoute.coach`.
- `HomeRoute.coach` renders `CoachInsightsView(insights: coachInsights)`.
- The same Home screen already has a proper `Your week` link in `CoachDecisionCardView`.

Important implication:

- Remove the `Details >` button from the Home `This week` card.
- Move insight access into `YourWeekView`, because `Your Week` is the correct weekly detail surface.

### Your Week

Relevant file:

- `Cadence/Cadence/Features/Coach/YourWeekView.swift`

Verified state:

- Current view inputs are:
  - `decision: CoachDecision`
  - `facts: CoachFacts`
  - `preferences: CoachSchedulePreferences`
- It generates a local `WeeklyPlan` from `facts` and `preferences`.
- Current sections are:
  - `This Week So Far`
  - `Planned (rest of week)`
  - `Planned (next week)`
  - optional `VO2max`
- It does not currently receive or render `coachInsights`.

### Coach Insights

Relevant files:

- `Cadence/Cadence/Features/Coach/CoachInsightsView.swift`
- `Cadence/Cadence/Features/Coach/CoachCardView.swift`

Verified state:

- `CoachInsightsView` is a full List screen.
- It renders each `Insight` with `InsightContentView`.
- `InsightContentView` is collapsed only for the "Why / the science" detail, but the row still shows the title and message.

Important implication:

- The requested `Coach's Insights` section should be more compact than the existing standalone list:
  - collapsed row: icon, title, and a small status/severity signal
  - no full message, no detailed science text, and no citation while collapsed
  - expansion reveals message, detail, and citation

### Why This Today

Relevant file:

- `Cadence/Cadence/Features/Coach/WhyThisTodayView.swift`

Verified state:

- The body renders, in order:
  - completed today banner
  - what you did
  - weekly balance
  - `Coach's Pick`
  - ruled out
  - why this won
  - warnings
  - `My Preferences`
- The `Coach's Pick` section always renders `decision.primary`.
- The `My Preferences` section embeds all schedule controls directly:
  - strength days per week
  - cardio days per week
  - rest pattern
  - fixed rest weekdays
  - rolling rest cadence
  - two-a-days
  - same-day cardio timing
  - citation links

Important implication:

- This is too dense for an explanation screen.
- After a completed plan, `decision.primary` can represent a next eligible candidate, not necessarily today's completed plan. Calling it `Coach's Pick` after Home says `Plan followed` is misleading.

### Settings

Relevant file:

- `Cadence/Cadence/Features/Settings/SettingsView.swift`

Verified state:

- `SettingsView` already has a bottom `Coach` section.
- Existing controls:
  - `Training goal`, accessibility id `settings.coach.goal`
  - `Experience`, accessibility id `settings.coach.experience`
- Existing UI tests expect those controls to remain reachable from Settings.

Important implication:

- Preserve those controls in Settings to avoid unnecessary test churn.
- Add a link or nested screen for schedule preferences, rather than moving everything to the top-level Settings form.

### Coach Completion And Add-Ons

Relevant files:

- `Cadence/Cadence/Features/Coach/CoachDecisionCardView.swift`
- `Cadence/Cadence/Features/Home/HomeView.swift`
- `CadenceCore/Sources/CadenceCore/CoachDecision.swift`
- `CadenceCore/Sources/CadenceCore/CoachAddOnEngine.swift`
- `CadenceCore/Sources/CadenceCore/PlanAdherence.swift`

Verified state:

- Home computes `coachDecision`.
- Home computes `addOnRecommendation` only when `coachDecision.planAdherence == .planComplete`.
- `CoachDecisionCardView` uses `planAdherence` to switch to a completed state:
  - eyebrow becomes `COACH - PLAN DONE`
  - it shows `Plan followed`
  - it hides the regular Start button
  - it can show optional add-ons such as `Add easy cardio`
- `WhyThisTodayView` receives only `CoachDecision`, not `CoachAddOnRecommendation`.
- Therefore, Why This Today cannot currently mirror Home's post-completion add-on context.

Important implication:

- Pass `addOnRecommendation` into `WhyThisTodayView`.
- In completed-plan state, do not render `Coach's Pick` for `decision.primary`.
- Show the completed plan summary and optional add-on context instead.

## Proposed Implementation Order

Implement in this order to keep the diff easy to review and tests easier to reason about:

1. Splash asset generation and `SplashView` restoration.
2. Home `This week` link removal.
3. Compact insights section in `YourWeekView`.
4. Coach schedule preferences extraction and navigation.
5. Why This Today completed-state reconciliation.
6. Tests and final cleanup.

## Phase 1 - Splash Image Restoration

### Desired Behavior

- The custom in-app splash should again use the `splash` image asset as a full-screen background.
- The background image should be grayscale.
- The background image should be resized and center-cropped to the intended iPhone splash resource canvas.
- The overlay text should remain readable on top of the image.
- The splash should still dismiss using the current timing and animation behavior.

### Resource Size Decision

Recommended target:

- `1320x2868` portrait.

Rationale:

- This matches the current large 6.9-inch iPhone portrait screenshot canvas listed by Apple.
- The app's `SplashView` uses `.aspectRatio(contentMode: .fill)`, so a large portrait asset can be downscaled and cropped cleanly on smaller devices.
- This is not a real static launch screen resource; it is a custom SwiftUI splash background.

Reference:

- Apple screenshot specifications: `https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications`

If the product team wants a different exact target, use that target consistently in the ImageMagick command and verify it with `identify`.

### Source Image Decision

Use the existing old image as the source. Options:

1. Preferred for reproducibility:
   - Extract the original image from git:
   - `git show 134d6b8:Cadence/Cadence/Assets.xcassets/splash.imageset/splash.jpg > /tmp/cladiron-old-splash.jpg`
2. Acceptable if no binary divergence has occurred:
   - Use current `Cadence/Cadence/Resources/splash.jpg` as source.

Before generating, compare hashes or dimensions if using both:

```sh
shasum Cadence/Cadence/Assets.xcassets/splash.imageset/splash.jpg Cadence/Cadence/Resources/splash.jpg
identify Cadence/Cadence/Assets.xcassets/splash.imageset/splash.jpg Cadence/Cadence/Resources/splash.jpg
```

### ImageMagick Command

Use ImageMagick 7 syntax:

```sh
magick /tmp/cladiron-old-splash.jpg \
  -auto-orient \
  -colorspace Gray \
  -resize 1320x2868^ \
  -gravity center \
  -extent 1320x2868 \
  -strip \
  -quality 88 \
  Cadence/Cadence/Assets.xcassets/splash.imageset/splash.jpg
```

If keeping `Cadence/Cadence/Resources/splash.jpg` as the source/original, do not overwrite it unless the team wants the duplicate resource to match the app asset. Since the project file does not appear to reference `Resources/splash.jpg`, the safer default is:

- App-rendered asset: overwrite `Assets.xcassets/splash.imageset/splash.jpg` with the generated grayscale `1320x2868` image.
- Source/archive image: leave `Resources/splash.jpg` unchanged.

If the agent decides the duplicate must match, explicitly note that choice in the final handoff.

### Verification Commands

```sh
identify Cadence/Cadence/Assets.xcassets/splash.imageset/splash.jpg
identify -format '%w x %h, %[colorspace]\n' Cadence/Cadence/Assets.xcassets/splash.imageset/splash.jpg
file Cadence/Cadence/Assets.xcassets/splash.imageset/splash.jpg
```

Expected:

- Dimensions: `1320 x 2868`
- Colorspace/type should indicate grayscale or gray-derived output.
- JPEG should still be valid.

### `SplashView.swift` Edit Plan

Restore image-backed behavior from commit `8c5e5f1`, with minimal changes:

- In `ZStack`, first try `UIImage(named: "splash")`.
- If present:
  - render with `Image(uiImage:)`
  - `.resizable()`
  - `.aspectRatio(contentMode: .fill)`
  - `.ignoresSafeArea()`
  - `.clipped()`
- If missing, fall back to `Color(.systemGray6)` or `Color(.systemBackground)`.
- Add a dark overlay for text contrast. Start with `Color.black.opacity(0.45)` because the asset will already be grayscale.
- Keep the current text:
  - `Cladiron`
  - `Your strength coach`
- Keep the current `opacity`, `scale`, timing, and dismissal behavior.
- Do not reintroduce the app-icon overlay unless the user requests it.

Suggested shape:

```swift
ZStack {
    if let image = UIImage(named: "splash") {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
            .clipped()
    } else {
        Color(.systemGray6)
            .ignoresSafeArea()
    }

    Color.black.opacity(0.45)
        .ignoresSafeArea()

    VStack(spacing: 14) {
        Text("Cladiron")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.white)

        Text("Your strength coach")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
    }
    .scaleEffect(scale)
    .opacity(opacity)
}
```

### Splash Acceptance Criteria

- App shows image-backed splash after onboarding is complete.
- Image is grayscale.
- Image covers the whole screen without letterboxing.
- Center crop is used, not stretching.
- Text is readable on light and dark portions of the image.
- Existing dismissal animation still works.
- No launch-screen build settings changed.

## Phase 2 - Remove Home `This week` `Details >`

### Desired Behavior

- Home `This week` card should be a compact metric card only.
- It should not contain `Details >`.
- Users should use the Coach card's `Your week` link for weekly detail.

### File

- `Cadence/Cadence/Features/Home/HomeView.swift`

### Edit Plan

In `thisWeekCard`:

- Remove the trailing `Button` in the header `HStack`.
- Keep the `Text("This week").font(.headline)`.
- Keep the `Spacer()` only if needed for layout; it is fine to leave it.
- Keep all four metrics:
  - strength
  - minutes
  - volume
  - parts

Current behavior to remove:

```swift
Button { Haptics.selection(); path.append(HomeRoute.coach) } label: {
    HStack(spacing: 3) {
        Text("Details").font(.caption)
        Image(systemName: "chevron.right").font(.caption2)
    }.foregroundStyle(.tint)
}
.buttonStyle(.plain)
```

After removal:

```swift
HStack {
    Text("This week").font(.headline)
    Spacer()
}
```

### Follow-Up Cleanup

After moving insights into `YourWeekView`, check whether `HomeRoute.coach` is still used.

Options:

1. Low-risk cleanup:
   - Leave `HomeRoute.coach` and `CoachInsightsView` in place even if unused.
   - This avoids accidental navigation churn.
2. Cleaner cleanup:
   - Remove `HomeRoute.coach`.
   - Remove the `case .coach` navigation destination.
   - Keep `CoachInsightsView` only if some other route still references it.

Recommended:

- Use option 1 for this pass unless the compiler flags dead or impossible code during related edits.

### Acceptance Criteria

- No `Details >` text appears inside Home `This week`.
- Home still shows all four weekly metrics.
- Coach card still has a `Your week` link.

## Phase 3 - Add Compact `Coach's Insights` To `YourWeekView`

### Desired Behavior

- `Your Week` becomes the weekly detail screen.
- At the bottom of `Your Week`, show `Coach's Insights`.
- Insights should be compact by default.
- Details should be hidden until the user expands a row.
- Expanded row should show:
  - message
  - detailed explanation
  - citation link

### Files

- `Cadence/Cadence/Features/Coach/YourWeekView.swift`
- `Cadence/Cadence/Features/Home/HomeView.swift`
- optionally `Cadence/Cadence/Features/Coach/CoachCardView.swift`

### Data Flow Plan

Change `YourWeekView` signature:

```swift
struct YourWeekView: View {
    let decision: CoachDecision
    let facts: CoachFacts
    let preferences: CoachSchedulePreferences
    let insights: [Insight]
}
```

Update `HomeView` route:

```swift
YourWeekView(
    decision: coachDecision,
    facts: facts,
    preferences: settings.coachSchedulePreferences,
    insights: coachInsights
)
```

Keep `coachInsights` computed in Home as it already exists.

### UI Placement

Add the new section after optional `VO2max`, so it is truly at the bottom.

Order:

1. `This Week So Far`
2. `Planned (rest of week)`
3. `Planned (next week)`
4. optional `VO2max`
5. `Coach's Insights`

If there are no insights:

- Omit the section, or show a single compact row:
  - `No insights yet`
  - `Log a few workouts and Coach will start spotting patterns.`

Recommended:

- Omit the section if `insights.isEmpty` to avoid filler.

### Compact Row Design

Create a local private view inside `YourWeekView.swift`:

```swift
private struct CompactInsightRow: View {
    let insight: Insight
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded.toggle()
            }
        } label: {
            ...
        }
        .buttonStyle(.plain)
    }
}
```

However, because expanded content contains a `NavigationLink` for `CitationLink`, avoid making the whole expanded area one big `Button` if that creates nested interactive controls. A safer layout:

```swift
VStack(alignment: .leading, spacing: 8) {
    Button { expanded.toggle() } label: {
        HStack(spacing: 10) {
            Image(systemName: insight.kind.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(insight.severityLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)

    if expanded {
        VStack(alignment: .leading, spacing: 6) {
            Text(insight.message)
            Text(insight.detail)
            CitationLink(citation: insight.citation, compact: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
```

If `InsightSeverity` has no display label, add a small local helper:

```swift
private extension InsightSeverity {
    var compactLabel: String {
        switch self {
        case .attention: return "Needs attention"
        case .info: return "Info"
        }
    }
}
```

Use existing `InsightKind.symbol` and `InsightSeverity.tint` extensions from `CoachCardView.swift`. They are file-scoped extensions in the module and should be available. If access fails due to scope, move those extensions to a small shared file or duplicate minimal private helpers in `YourWeekView.swift`.

### Accessibility

Add identifiers:

- Section list exists through text `Coach's Insights`.
- Collapsed row:
  - `yourWeek.insight.<insight.id>`
- Toggle button:
  - `yourWeek.insight.<insight.id>.toggle`
- Expanded detail:
  - `yourWeek.insight.<insight.id>.detail`

Example:

```swift
.accessibilityIdentifier("yourWeek.insight.\(insight.id)")
```

### Acceptance Criteria

- `Your Week` shows `Coach's Insights` at the bottom when insights exist.
- Rows are compact when collapsed.
- No insight detail/citation is visible until expansion.
- Expansion works per row.
- Citation links still navigate to `CitationDetailView`.
- Home no longer routes insights from the `This week` card.

## Phase 4 - Move Schedule Preferences Out Of `Why This Today`

### Desired Behavior

- `Why This Today` should explain the recommendation, not host a full preferences editor.
- It should show a compact preferences summary and a `Review my preferences >` link.
- The full schedule preference controls should live behind that link and also be reachable from Settings.

### Files

- `Cadence/Cadence/Features/Coach/WhyThisTodayView.swift`
- `Cadence/Cadence/Features/Settings/SettingsView.swift`
- new recommended file: `Cadence/Cadence/Features/Coach/CoachSchedulePreferencesView.swift`

### New View Plan

Create a new SwiftUI view:

```swift
struct CoachSchedulePreferencesView: View {
    @Environment(AppSettings.self) private var settingsObject

    var body: some View {
        @Bindable var settings = settingsObject
        Form {
            ...
        }
        .navigationTitle("Coach preferences")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

Move the schedule controls from `WhyThisTodayView.myPreferencesSection` into this new view:

- Strength days/week segmented picker.
- Cardio days/week segmented picker.
- Rest pattern segmented picker.
- Fixed day chips.
- Rolling rest stepper.
- Two-a-days toggle.
- Same-day cardio timing segmented picker.
- Existing science citation links.

Do not move the existing Settings `Training goal` and `Experience` pickers unless desired. Keep them in Settings because tests expect:

- `settings.coach.goal`
- `settings.coach.experience`

### Settings Integration

In `SettingsView`, update the `Coach` section to add a link:

```swift
NavigationLink {
    CoachSchedulePreferencesView()
} label: {
    Label("Schedule preferences", systemImage: "calendar.badge.clock")
}
.accessibilityIdentifier("settings.coach.schedulePreferences")
```

Keep existing `Training goal` and `Experience` pickers in the same section.

Suggested order:

1. Training goal
2. Experience
3. Schedule preferences link

### Why This Today Replacement Section

Replace `myPreferencesSection` with a compact link section, for example:

```swift
private var preferencesLinkSection: some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("My preferences")
            .font(.headline)
            .padding(.bottom, 4)

        NavigationLink {
            CoachSchedulePreferencesView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preferencesSummary)
                        .font(.subheadline.weight(.medium))
                    Text("Review my preferences")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("whyToday.preferences.review")
    }
}
```

Preference summary helper:

```swift
private var preferencesSummary: String {
    let prefs = settings.coachSchedulePreferences
    return "\(prefs.strengthDaysPerWeek) strength / \(prefs.cardioDaysPerWeek) cardio days"
}
```

Optional second line:

```swift
Text("\(prefs.restPreference.displayName) rest")
```

Keep the link label text exactly:

- `Review my preferences`

The user asked for `Review my preferences >`; in SwiftUI use text plus a chevron icon instead of a literal `>` character unless the visual design elsewhere uses literal chevrons.

### Acceptance Criteria

- `Why This Today` no longer contains segmented pickers, steppers, toggles, or fixed-day chips.
- `Why This Today` contains a compact `My preferences` section.
- The section has a `Review my preferences` navigation link.
- Settings has a path to the same schedule preferences screen.
- Existing Settings goal/experience tests still pass.

## Phase 5 - Reconcile Home `COACH` With `Why This Today`

### Problem

Home can show:

- `COACH - PLAN DONE`
- `Plan followed`
- optional `Add easy cardio`

But `Why This Today` can still show:

- `Coach's Pick`
- `Lighter strength session`

This is misleading because the user sees Home saying today's plan is complete, while the explanation screen presents a new primary recommendation as if it is still today's required plan.

### Root Cause

- Home uses `decision.planAdherence` to switch presentation state.
- Home uses `CoachAddOnEngine` for post-completion optional add-ons.
- `WhyThisTodayView` only receives `CoachDecision`.
- `WhyThisTodayView.coachPickSection` always renders `decision.primary`.
- `CoachDecision.primary` is still the top currently eligible candidate after same-day dampening and completion checks. In a completed state, it should not be presented as today's pick.

### Desired Behavior

When `decision.planAdherence == .planComplete`:

- `Why This Today` should foreground the completed plan.
- It should not show the `Coach's Pick` heading.
- It should not show `decision.primary` as today's required action.
- It should show optional add-on context consistent with Home:
  - primary add-on such as `Add easy cardio`, if encouraged
  - secondary add-ons behind expansion, if present
  - warnings for add-ons if relevant
- `Why this won` should be hidden or renamed because it otherwise explains why `decision.primary` won, which is not what Home is presenting.

Recommended:

- Hide `coachPickSection` and `whyWonSection` in `.planComplete`.
- Add a `completedPlanExplanationSection`.
- Add an `optionalAddOnsSection`.

### Data Flow Change

Update `WhyThisTodayView` signature:

```swift
struct WhyThisTodayView: View {
    let decision: CoachDecision
    let addOnRecommendation: CoachAddOnRecommendation
    var onAltTap: (() -> Void)?
    var onAddOnTap: ((CoachSession, CoachAddOnStatus) -> Void)?
}
```

Minimum version if not launching add-ons from Why:

```swift
struct WhyThisTodayView: View {
    let decision: CoachDecision
    let addOnRecommendation: CoachAddOnRecommendation
    var onAltTap: (() -> Void)?
}
```

Recommended:

- Include `onAddOnTap` if Why should allow starting optional add-ons.
- If not, show add-ons as explanatory only and avoid buttons.

Update `HomeView`:

```swift
WhyThisTodayView(
    decision: coachDecision,
    addOnRecommendation: addOnRecommendation,
    onAltTap: { path.append(HomeRoute.coachAlternatives) },
    onAddOnTap: { session, status in handleAddOn(session, status) }
)
```

### Body Branching Plan

In `WhyThisTodayView.body`, replace unconditional `coachPickSection` and `whyWonSection` with state-aware branches.

Current:

```swift
completedTodaySection
whatYouDidSection
weeklyBalanceSection
coachPickSection
ruledOutSection
whyWonSection
warningsSection
myPreferencesSection
```

Planned:

```swift
completedTodaySection
whatYouDidSection
weeklyBalanceSection

if isPlanComplete {
    completedPlanExplanationSection
    optionalAddOnsSection
} else {
    coachPickSection
    ruledOutSection
    whyWonSection
}

warningsSection
preferencesLinkSection
```

Decision:

- Keep `ruledOutSection` hidden during plan complete unless user research says it is helpful. It currently references current candidates and may reinforce the contradiction.
- Keep `warningsSection` because warnings can apply generally, but make sure the copy is not framed as a new required workout.

Helper:

```swift
private var isPlanComplete: Bool {
    if case .planComplete = decision.planAdherence { return true }
    return false
}
```

### Completed Plan Section

Add a section that uses `PlanAdherence.planComplete` fields:

```swift
private var completedPlanExplanationSection: some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("Today's plan")
            .font(.headline)
            .padding(.bottom, 4)

        card(highlight: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Plan followed")
                        .font(.subheadline.weight(.bold))
                }

                Text(todayCompleteDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let tomorrow = tomorrowPreview {
                    Label("Tomorrow: \(tomorrow)", systemImage: "forward.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
        }
    }
}
```

Use existing helpers or add:

```swift
private var todayCompleteDescription: String {
    if case .planComplete(_, let desc, _) = decision.planAdherence { return desc }
    return ""
}

private var tomorrowPreview: String? {
    if case .planComplete(_, _, let preview) = decision.planAdherence { return preview }
    return nil
}
```

### Optional Add-Ons Section

Render only if `addOnRecommendation` has at least one option.

Data:

```swift
let primary = addOnRecommendation.primaryOption
let secondary = addOnRecommendation.secondaryOptions
```

Collapsed default:

- Show primary encouraged add-on directly if present.
- Hide secondary add-ons behind a `More options` button.

Copy:

- Section title: `Optional after today`
- Primary button/row title should use `option.session.title`, e.g. `Add easy cardio`.
- Message should use `option.message`.
- Status should be visible but compact:
  - encouraged: green, `Encouraged`
  - neutral: secondary, `Optional`
  - warn: orange, `Caution`

If add-ons are explanatory only:

- Use a non-button row.

If add-ons are actionable:

- Call `onAddOnTap?(option.session, option.status)`.
- Reuse Home's warning behavior by passing through `handleAddOn`.

Avoid duplicating a lot of private Home-only code:

- Create a small shared `CoachAddOnOptionRow` view in a Coach feature file, or duplicate a minimal row in `WhyThisTodayView` if the styles differ.
- Do not expose Home internals.

### What To Do With `CoachAlternativesView`

In completed-plan state:

- Do not show the existing `Alternatives` button in `coachPickSection`, because `coachPickSection` is hidden.
- Do not route to `CoachAlternativesView` from completed Why state.

In normal state:

- Keep existing Alternatives behavior.

### Acceptance Criteria

- If Home says `Plan followed`, Why This Today also says `Plan followed`.
- In completed-plan state, Why This Today does not show `Coach's Pick`.
- In completed-plan state, Why This Today does not show `Lighter strength session` or another `decision.primary` session as today's required action.
- If Home shows `Add easy cardio`, Why This Today shows the same optional add-on context.
- Normal non-completed Why This Today still shows `Coach's Pick`, alternatives, ruled-out candidates, and why-won claims.

## Phase 6 - Tests

### Core Tests

Run existing core tests after UI changes if no core changes were made:

```sh
swift test --package-path CadenceCore
```

If core changes are made, add or update tests in:

- `CadenceCore/Tests/CadenceCoreTests/CoachDecisionEngineTests.swift`
- `CadenceCore/Tests/CadenceCoreTests/CoachSchedulePreferencesTests.swift`

Recommended core addition only if touching core:

- A test asserting `planAdherence == .planComplete` does not require `decision.primary` to be presented as the completed workout. This may be better documented in UI tests rather than enforced in core.

### UI Tests To Add Or Update

Relevant files:

- `Cadence/CadenceUITests/P3CoachHomeUITests.swift`
- `Cadence/CadenceUITests/WhyThisTodayUITests.swift`

#### Test 1 - Home No Longer Shows `Details` In `This week`

Add to `P3CoachHomeUITests` or a Home polish test:

```swift
func testThisWeekCardDoesNotShowDetailsLink() {
    let app = XCUIApplication.launched()
    XCTAssertTrue(app.descendants(matching: .any)["home.thisWeek"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Details"].exists)
}
```

If `buttons["Details"]` is too broad, scope through descendants of `home.thisWeek` if helper support exists.

#### Test 2 - Your Week Contains Compact Coach Insights

Seed with a state that produces insights, likely `coachWhyMixedHistory` or default data.

Flow:

1. Launch app.
2. Tap `coach.card.yourWeek`.
3. Assert navigation bar `Your week`.
4. Scroll to `Coach's Insights`.
5. Assert at least one `yourWeek.insight.*` row exists.
6. Assert detail identifier is absent before expansion.
7. Tap row.
8. Assert detail identifier appears.

Suggested test:

```swift
func testYourWeekShowsCompactExpandableCoachInsights() {
    let app = XCUIApplication.launched(seeds: ["coachWhyMixedHistory"])
    XCTAssertTrue(app.buttons["coach.card.yourWeek"].waitForExistence(timeout: 10))
    app.buttons["coach.card.yourWeek"].tap()
    XCTAssertTrue(app.navigationBars["Your week"].waitForExistence(timeout: 5))

    app.swipeUp()
    XCTAssertTrue(app.staticTexts["Coach's Insights"].waitForExistence(timeout: 5))

    let row = app.descendants(matching: .any).matching(identifierPrefix: "yourWeek.insight.").firstMatch
    XCTAssertTrue(row.exists)
}
```

If no identifier-prefix helper exists, add a stable identifier to the first insight row, or assert via title text from a known seeded insight.

#### Test 3 - Why Today Preferences Link

Add to `WhyThisTodayUITests`:

```swift
func testWhyTodayHidesPreferenceControlsBehindReviewLink() {
    let app = XCUIApplication.launched(seeds: ["coachWhyMixedHistory"])
    app.buttons["coach.card.whyToday"].tap()
    XCTAssertTrue(app.navigationBars["Why this today"].waitForExistence(timeout: 5))

    XCTAssertTrue(app.buttons["whyToday.preferences.review"].exists)
    XCTAssertFalse(app.segmentedControls["Strength days"].exists)
    XCTAssertFalse(app.switches["Two-a-days"].exists)

    app.buttons["whyToday.preferences.review"].tap()
    XCTAssertTrue(app.navigationBars["Coach preferences"].waitForExistence(timeout: 5))
}
```

Adjust selectors to match actual SwiftUI accessibility output.

#### Test 4 - Settings Can Open Schedule Preferences

Extend `P3CoachHomeUITests.testCoachSettingsPickersExist` or add a new test:

```swift
func testSettingsLinksToCoachSchedulePreferences() {
    let app = XCUIApplication.launched()
    app.buttons["home.settings"].tap()
    let link = app.buttons["settings.coach.schedulePreferences"]
    if !link.exists || !link.isHittable {
        app.swipeUp()
        app.swipeUp()
    }
    XCTAssertTrue(link.waitForExistence(timeout: 5))
    link.tap()
    XCTAssertTrue(app.navigationBars["Coach preferences"].waitForExistence(timeout: 5))
}
```

Keep the existing assertions for:

- `settings.coach.goal`
- `settings.coach.experience`

#### Test 5 - Completed Plan Why Today Does Not Show Contradictory Pick

This directly covers the user's reported issue.

Add to `WhyThisTodayUITests`:

```swift
func testWhyTodayPlanCompleteDoesNotShowCoachPick() {
    let app = XCUIApplication.launched(seeds: ["coachWednesdayComplete"])
    XCTAssertTrue(app.buttons["coach.card.whyToday"].waitForExistence(timeout: 10))
    app.buttons["coach.card.whyToday"].tap()
    XCTAssertTrue(app.navigationBars["Why this today"].waitForExistence(timeout: 5))

    XCTAssertTrue(app.staticTexts["Plan followed"].exists)
    XCTAssertFalse(app.staticTexts["Coach's Pick"].exists)
    XCTAssertFalse(app.staticTexts["Lighter strength session"].exists)
}
```

If `Lighter strength session` is not reliably present in that seed, the important assertion is absence of `Coach's Pick`.

If add-ons are shown in Why:

```swift
XCTAssertTrue(app.staticTexts["Optional after today"].exists)
XCTAssertTrue(app.staticTexts["Add easy cardio"].exists || app.staticTexts["Easy movement"].exists)
```

### Test Commands

Core:

```sh
swift test --package-path CadenceCore
```

Targeted UI examples:

```sh
xcodebuild test \
  -project Cadence/Cadence.xcodeproj \
  -scheme Cadence \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CadenceUITests/WhyThisTodayUITests
```

```sh
xcodebuild test \
  -project Cadence/Cadence.xcodeproj \
  -scheme Cadence \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CadenceUITests/P3CoachHomeUITests
```

If simulator availability differs, first run:

```sh
xcrun simctl list devices available
```

or use the existing approved project test destination in the repo's normal workflow.

## Phase 7 - Manual QA Checklist

Run through these manually in the simulator:

1. Fresh launch with onboarding complete:
   - Splash uses grayscale image.
   - Text is readable.
   - Splash dismisses.
2. Home:
   - Coach card appears.
   - `This week` card has no `Details >`.
   - `This week` metrics remain aligned.
3. Home -> Coach card -> `Your week`:
   - Existing week sections still render.
   - `Coach's Insights` appears at bottom when insights exist.
   - Insight rows are compact.
   - Tapping one expands details.
   - Citation link works.
4. Home -> Coach card -> `Why this today` in normal state:
   - `Coach's Pick` still appears.
   - Alternatives still opens.
   - Preferences are only a compact link.
5. Home -> Coach card -> `Why this today` in `coachWednesdayComplete` seed:
   - `Plan followed` appears.
   - `Coach's Pick` does not appear.
   - No contradictory `Lighter strength session` is presented as required.
   - Optional add-on copy matches Home.
6. Settings:
   - Training goal and Experience remain reachable.
   - Schedule preferences link opens.
   - Schedule controls persist changes.

## Risk Notes

### Risk 1 - Image Cropping Removes Important Subject

The source image is `1280x1920` and target `1320x2868` is much taller/narrower. Center cropping after height-fit will remove side content. The agent should inspect the generated image visually.

Mitigation:

- Generate once with `-gravity center`.
- If subject is off-center, try `-gravity north`, `-gravity south`, or a manual crop offset.
- Do not use stretching to fit.

### Risk 2 - Actual Launch Screen Confusion

The project uses Xcode generated launch screen. Restoring `SplashView` does not affect the earliest iOS launch frame.

Mitigation:

- Mention in final handoff.
- Do not alter launch-screen settings in this pass.

### Risk 3 - Nested Buttons In Insight Rows

Expanded insight rows include citation `NavigationLink`. If the entire row is a `Button`, nested controls can behave badly.

Mitigation:

- Make only the header/toggle a Button.
- Put expanded text and citation outside the Button.

### Risk 4 - Settings Tests

Existing tests expect `settings.coach.goal` and `settings.coach.experience`.

Mitigation:

- Keep those controls in Settings.
- Add schedule preferences as a link below them.

### Risk 5 - Completed State Still Uses `decision.primary` Elsewhere

It is okay for `decision.primary` to remain the current eligible candidate internally. The bug is presenting it as `Coach's Pick` after plan completion.

Mitigation:

- Branch UI on `planAdherence`.
- Pass `addOnRecommendation` into Why.
- Add completed-state UI test.

## Suggested File Change List

Expected source edits:

- `Cadence/Cadence/App/SplashView.swift`
- `Cadence/Cadence/Assets.xcassets/splash.imageset/splash.jpg`
- `Cadence/Cadence/Features/Home/HomeView.swift`
- `Cadence/Cadence/Features/Coach/YourWeekView.swift`
- `Cadence/Cadence/Features/Coach/WhyThisTodayView.swift`
- `Cadence/Cadence/Features/Settings/SettingsView.swift`
- new `Cadence/Cadence/Features/Coach/CoachSchedulePreferencesView.swift`
- `Cadence/CadenceUITests/WhyThisTodayUITests.swift`
- `Cadence/CadenceUITests/P3CoachHomeUITests.swift`

Optional edits:

- `Cadence/Cadence/Features/Coach/CoachInsightsView.swift` if comments need updating.
- `Cadence/Cadence/Features/Coach/CoachCardView.swift` if shared `InsightKind` or `InsightSeverity` helpers need to move.
- `Cadence/Cadence/Resources/splash.jpg` only if choosing to keep duplicate splash resources in sync.

Avoid:

- `Cadence/Cadence/Info.plist`
- `Cadence/Cadence.xcodeproj/project.pbxproj`, unless image asset catalog behavior unexpectedly requires project changes.
- `CadenceCore` source, unless a focused test proves a core model change is necessary.

## Final Handoff Expectations For The Coding Agent

When implementation is complete, the agent should report:

- Exact splash image dimensions and colorspace from `identify`.
- Whether `Resources/splash.jpg` was left unchanged or synced.
- Which screens changed.
- Which tests were run and their results.
- Any tests not run and why.
- Confirmation that `revisions-plan.md` was not touched unless explicitly requested.

