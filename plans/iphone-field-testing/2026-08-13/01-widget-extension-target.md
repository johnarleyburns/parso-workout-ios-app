# Widget Extension Target Plan — 2026-08-13

## Objective

Add a real iOS Widget Extension target for the existing ActivityKit workout state so an active iPhone workout appears on the Lock Screen and Dynamic Island. Keep the current app-owned ActivityKit coordinator as the lifecycle owner, and make the shared attributes available to both the app and widget targets.

## Current state

- `Cadence/Cadence/LiveActivity/WorkoutLiveActivity.swift` currently defines the ActivityKit attributes and app-side coordinator.
- The iOS app has `NSSupportsLiveActivities = true` in `Cadence/Cadence/Info.plist`.
- The Xcode project currently contains the iPhone app, Watch app, unit-test, and UI-test targets, but no Widget Extension target.
- The app bundle identifier is `guru.parso.ios-workout-app`; the new extension should use `guru.parso.ios-workout-app.widget` unless provisioning constraints require the team’s established suffix.
- The Watch app should continue using its native HealthKit workout surface; no watch widget target is needed for this feature.

## Implementation design

### 1. Create the extension target

Add an iOS Widget Extension target named `CadenceLiveActivity` to `Cadence/Cadence.xcodeproj` with:

- Deployment target matching the ActivityKit minimum supported by the app and the project’s current iOS deployment policy.
- Product type `com.apple.product-type.app-extension` and extension point `com.apple.widgetkit-extension`.
- Bundle identifier `guru.parso.ios-workout-app.widget`.
- Swift version and signing team/style matching the iPhone app.
- A dedicated `CadenceLiveActivity.entitlements` file if Xcode requires one; do not add App Groups unless implementation proves they are needed, because ActivityKit transfers state through the system.
- An extension `Info.plist` containing the WidgetKit extension point and the supported live-activity configuration.
- Embed the extension in the iPhone application’s Frameworks/PlugIns build phase and ensure Release/TestFlight archive settings include it.

Prefer using Xcode’s target-generation workflow or a carefully reviewed project-file edit so build phases, target dependencies, schemes, and signing settings are all represented consistently in the project file.

### 2. Split shared ActivityKit types from app lifecycle code

Move `WorkoutLiveActivityAttributes` and its `ContentState` into a shared source file included in both the iPhone app and widget targets, for example `Cadence/Cadence/LiveActivity/WorkoutLiveActivityAttributes.swift`.

Keep `WorkoutLiveActivityCoordinator` in an app-only source file. The shared attributes must remain free of app-only dependencies and should contain only Codable/Hashable/Sendable ActivityKit state:

- workout title
- phase/status
- elapsed seconds
- paused state

The widget target must not import or depend on the app target. If the project’s synchronized groups make target membership ambiguous, explicitly set target membership in the project file and verify duplicate-symbol avoidance.

### 3. Implement Lock Screen and Dynamic Island views

Add a WidgetKit `WidgetBundle`/Live Activity implementation that:

- Uses `ActivityConfiguration(for: WorkoutLiveActivityAttributes.self)`.
- Shows a compact, glanceable workout title and elapsed time.
- Shows an expanded view with phase/status and paused/running treatment.
- Provides a Lock Screen presentation that remains legible in Always-On/dimmed states.
- Uses `Text(timerInterval:)` or an equivalent system-driven timer for elapsed time so the widget updates without app-side per-second rendering work.
- Handles stale or missing state gracefully.
- Uses accessibility labels and identifiers where practical for UI testing.

The widget must render `Active`, `Paused`, and cooldown/finished transitions consistently with the coordinator’s state contract. The app should continue ending the activity immediately when the workout is ended or discarded.

### 4. Verify app lifecycle integration

Review the coordinator and `RootTabView` integration after the target exists:

- Confirm only one live activity is started for an active workout.
- Confirm repeated scene/heartbeat updates update the existing activity rather than creating duplicates.
- Confirm pause/resume updates state.
- Confirm strength and supported cardio flows use the same activity contract, or explicitly limit the feature to strength with a documented reason.
- Confirm app relaunch/recovery does not orphan an activity.
- Confirm ActivityKit authorization denial is a safe no-op.

## Tests and smoke coverage

### Unit tests

Add tests for pure shared-state behavior where possible:

- Activity content-state construction for active, paused, and cooldown phases.
- Stable title/status mapping for strength, HIIT, and other supported cardio sessions.
- Elapsed-time and pause-state transitions.
- Finished/discarded state does not remain active.

Keep ActivityKit framework calls behind the coordinator so the unit tests do not require an actual Lock Screen or simulator activity.

### iPhone UI smoke test additions

Extend the iPhone smoke test or add a focused test that:

1. Starts a workout.
2. Verifies the workout is active and the ActivityKit coordinator receives an active state through a test seam or launch diagnostic.
3. Exercises pause/resume if the smoke-test runtime supports it.
4. Ends the workout and verifies the activity-end path is invoked.

Do not make the test depend solely on scraping the simulator Lock Screen; use a deterministic app-side test hook for lifecycle assertions, with manual/device validation for the actual Lock Screen rendering.

### Build and archive checks

Run and record:

- `swift test --package-path CadenceCore`.
- `scripts/check-test-pyramid.sh` and `scripts/check-no-network.sh`.
- iPhone UI smoke test.
- `xcodebuild build-for-testing` for the iPhone scheme, proving the extension target compiles and embeds.
- A Release/archive or CI TestFlight build proving signing, extension embedding, and export succeed.

## Manual acceptance checklist

- Start a strength workout on a physical iPhone running a supported iOS version.
- Lock the phone; confirm the Live Activity appears on the Lock Screen.
- Confirm elapsed time advances while the phone is locked.
- Confirm pause/resume changes the displayed state.
- Confirm the expanded Dynamic Island and compact presentation are readable where available.
- Confirm cooldown/finished state and dismissal behavior.
- Confirm ending/discarding a workout removes the activity.
- Confirm the Watch experience remains unchanged and continues to use its native workout surface.

## Risks and mitigations

- Manual signing may require a new App ID/capability for the extension. Validate provisioning before merging project-file changes.
- Widget extensions have stricter deployment and API availability constraints. Gate newer Dynamic Island APIs with availability checks.
- Xcode synchronized groups can make source membership implicit. Verify the generated target’s Compile Sources list and avoid duplicate shared-type compilation.
- CI archives the app for TestFlight, so a simulator-only target setup is insufficient; test the Release archive path before merging.

## Definition of done

- The project contains a signed, embedded Widget Extension target.
- Shared ActivityKit attributes compile in both app and extension without duplicate symbols.
- Lock Screen and Dynamic Island views render active and paused workouts.
- Unit tests and iPhone smoke coverage pass.
- Local archive/build and CI TestFlight validation pass.
- README/current state are updated to remove the current “coordinator only” limitation.
