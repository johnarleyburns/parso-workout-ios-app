# Swift 6 Migration and Warning-Elimination Plan

## Objective

Move every Cladiron Swift package and Xcode target to Swift 6 language mode in
one coordinated change set. The completed migration must compile and test with
no warnings attributable to source, manifests, resources, scripts, or build
settings owned by this repository.

Warnings emitted solely by Apple-generated code or the selected Xcode toolchain
may be exempted only through a narrow, reviewed allowlist. Each exception must
identify the exact diagnostic, affected toolchain, reason it cannot be fixed in
owned source, and the condition for removing it.

## Current Baseline

The repository currently uses a Swift 6 compiler without using Swift 6 language
semantics:

- The local compiler is Swift 6.3.3 from Xcode 26.6.
- `CadenceCore/Package.swift` declares Swift tools version 5.10.
- All 12 Xcode build configurations declare `SWIFT_VERSION = 5.0`.
- No target explicitly enables complete strict-concurrency checking.
- CI runs SwiftPM tests and a signed Release archive, but does not reject
  successful builds that emit warnings.

An exploratory build with complete concurrency checking found these initial
owned-code warning groups. This is a starting inventory, not a closed list;
Swift 6 can reveal later diagnostics only after earlier errors are fixed.

| Area | Current diagnostic | Required direction |
| --- | --- | --- |
| SwiftData history | `WorkoutHistoryEntry: Sendable` contains non-Sendable `@Model` classes | Keep models actor-bound; remove the invalid conformance and isolate history construction |
| Watch workout manager | Session delegates, tasks, and closures send mutable manager state across isolation boundaries | Main-actor isolate manager state and bridge delegate callbacks explicitly |
| WatchConnectivity | `WCSession` and `[String: Any]` cross concurrency boundaries | Parse framework payloads into immutable Sendable values before actor hops |
| Watch timers | Sendable timer closures mutate observable workout state | Use actor-aware tasks/timers that re-enter the owning actor |
| Health providers | Real and fake providers use `@unchecked Sendable` | Give the protocol and implementations explicit actor ownership |
| Cardio configuration | `WorkoutConfigurationSpec` values cross tasks without Sendable conformance | Make the value and nested enums Sendable |
| CoreBluetooth | Shared `CBUUID` values are diagnosed as non-Sendable state | Keep raw identifiers Sendable and construct framework objects at the isolated boundary |
| SwiftData predicates | Generated predicate key paths may be diagnosed as non-Sendable | Prefer an equivalent source formulation; allowlist only if the active compiler still emits generated-code diagnostics |
| Volume guidance | Owned code reads deprecated `mev`, `mav`, and `mrv` properties | Migrate all call sites to range-based `VolumeGuidance` semantics with behavioral tests |
| Package resources | The vendored exercise-database license is unhandled | Explicitly declare it as a resource or exclude it after confirming distribution requirements |
| Access control | A redundant `public` modifier exists inside a public extension | Remove the redundant modifier |
| AppIntents metadata | Xcode reports metadata extraction skipped when no AppIntents dependency exists | Treat as toolchain output, not an owned warning, if it persists after migration |

## Migration Design

### Compiler and project settings

- Change `CadenceCore/Package.swift` to `// swift-tools-version: 6.0`. Swift 6.0
  preserves the repository's documented Xcode 16+ minimum instead of coupling
  the project to the newest local compiler.
- Set `SWIFT_VERSION = 6.0` in every Debug and Release configuration for the iOS
  app, watch app, unit-test, and UI-test targets.
- Set `SWIFT_STRICT_CONCURRENCY = complete` explicitly in all owned targets so
  the intended checking level remains visible in project configuration.
- Do not enable global default main-actor isolation. Assign actors at the type or
  member that owns mutable state so package logic remains usable off the main
  actor where it is genuinely safe.
- Preserve iOS 17, watchOS 10, and macOS 14 deployment targets and introduce no
  new dependency.

### Concurrency ownership

- Mark observable app and watch controllers that directly drive UI or
  framework-owned UI state as `@MainActor`, including their construction and
  mutable public interfaces.
- Make immutable cross-task inputs and results conform to `Sendable`, including
  `WorkoutConfigurationSpec` and its nested enums. Prefer small value snapshots
  over sending managers, SwiftData models, framework objects, or heterogeneous
  dictionaries.
- Remove `Sendable` from `WorkoutHistoryEntry`. Its associated SwiftData models
  remain on the actor that owns their `ModelContext`; mark the repository and
  presenter history-building APIs `@MainActor` where needed.
- Make `HealthDataProviding` main-actor isolated and update `HealthKitProvider`
  and `FakeHealthProvider` accordingly. Remove both `@unchecked Sendable`
  conformances. HealthKit operations remain asynchronous, so awaiting system
  queries does not turn them into blocking main-thread work.
- Treat HealthKit, WatchKit, WatchConnectivity, CoreBluetooth, and timer delegate
  callbacks as framework boundaries. A callback may be `nonisolated`; it must
  extract immutable Sendable data and enter `Task { @MainActor in ... }` before
  reading or mutating actor-owned state.
- Parse `[String: Any]` WatchConnectivity messages on the callback boundary into
  typed Sendable commands/preferences. Never capture the dictionary or
  `WCSession` inside a task sent to another actor.
- Use `@preconcurrency import` only when an Apple framework's annotations remain
  incomplete after the source is correctly isolated. Add an adjacent comment
  naming the framework boundary and do not use it for first-party modules.
- Do not add new `@unchecked Sendable`, `nonisolated(unsafe)`, or
  `MainActor.assumeIsolated` escape hatches. Audit the existing
  `MainActor.assumeIsolated` use in `IntervalCueScheduler` and replace it if the
  timer can enter the actor directly.

### Warning cleanup

- Add the database license to the package resource declaration when it must ship
  with the dataset; otherwise explicitly exclude it and retain the existing
  repository copy. Confirm the resulting app still contains all legally
  required attribution.
- Remove redundant access modifiers and all other straightforward compiler,
  linker, asset-catalog, localization, and build-setting warnings found by clean
  builds.
- Replace internal use of deprecated volume landmarks with
  `VolumeGuidance.startingTargetRange` and
  `VolumeGuidance.personalBaselineRange`. Preserve the existing coach's numeric
  behavior until a separately reviewed product change intentionally alters it.
  Keep compatibility wrappers only if an owned caller still needs them; owned
  production code and tests must not invoke deprecated APIs.
- For generated SwiftData predicate diagnostics, first rewrite the query or move
  filtering to an actor-isolated source path without changing results. Add an
  exception only if a minimal reproduction confirms the warning belongs to the
  selected Swift/Xcode toolchain.
- Represent Bluetooth UUID constants as Sendable strings or raw values and
  create `CBUUID` instances inside the main-actor Bluetooth service.
- Repeat clean builds after each warning group is resolved because the compiler
  can suppress downstream diagnostics after an error.

## Warning Gate and CI

Add `scripts/check-owned-warnings.sh` as the single warning classifier used
locally and in CI. It accepts one or more build logs and exits nonzero when it
finds an unclassified `warning:` diagnostic attributed to this repository.

The script must:

- Normalize absolute checkout and DerivedData paths before matching.
- Treat diagnostics originating from `Cadence`, `CadenceCore`, package manifests,
  asset catalogs, build phases, and repository scripts as owned.
- Store toolchain-only exceptions as exact anchored patterns in the script with
  a comment containing Xcode/Swift version, rationale, and removal condition.
- Print every rejected diagnostic and every used exception; fail when an
  exception becomes overly broad or when an owned path is not classified.
- Include fixture tests for accepted owned-free logs, rejected owned warnings,
  and each allowlisted toolchain diagnostic.

Update the `core-tests` job to capture both `swift build` and `swift test` logs
with `set -o pipefail`, then run the classifier. Update the TestFlight archive
job to classify its existing `build.log` immediately after a successful archive
and before export/upload. Upload the build log whenever either compilation or
warning classification fails.

Do not globally set `SWIFT_TREAT_WARNINGS_AS_ERRORS` or
`GCC_TREAT_WARNINGS_AS_ERRORS`: those settings would turn Apple-generated
diagnostics into failures before the repository-owned classifier can apply its
reviewed exceptions. Swift 6 errors remain normal compiler failures.

## Implementation Sequence

The migration lands as one coordinated change set, but work proceeds in this
order so every diagnostic is handled deliberately:

1. Add warning-classifier fixtures and establish saved clean-build logs for
   SwiftPM, iOS, and watchOS.
2. Remove non-concurrency warnings while still in Swift 5 mode, including the
   package resource, redundant access control, deprecated volume APIs, generated
   predicates, and Bluetooth constants.
3. Enable complete concurrency checking in Swift 5 mode and resolve every
   warning through actor ownership and Sendable value boundaries.
4. Change the package and Xcode language settings to Swift 6, then iterate clean
   package, iOS, and watchOS builds until no new owned diagnostic remains.
5. Enable the warning classifier in both CI jobs, update migration/current-state
   documentation, and run the full acceptance matrix before committing.

No intermediate state is merged to `main`. The final change must contain the
settings switch, source fixes, tests, warning gate, and documentation together.

## Public Interface Changes

- The package requires Swift tools/language version 6.0.
- `WorkoutConfigurationSpec` and other immutable task-boundary values gain
  `Sendable` conformance.
- `WorkoutHistoryEntry` no longer claims `Sendable`; history APIs that expose
  SwiftData models become main-actor isolated.
- `HealthDataProviding` becomes actor-isolated, and callers construct and invoke
  providers from that actor.
- Deprecated `VolumeBands` members are no longer used by owned callers. Any
  retained compatibility surface remains deprecated and is tested separately
  from the production range-based path.

These are source-level concurrency changes only. They do not alter SwiftData or
CloudKit schemas, persisted preferences, WatchConnectivity wire keys, JSON
exports, deployment targets, or user-visible behavior.

## Test and Acceptance Matrix

Run from a clean checkout using the CI-selected Xcode version:

```sh
swift build --package-path CadenceCore
swift test --package-path CadenceCore
bash scripts/check-test-pyramid.sh
bash scripts/check-no-network.sh

xcodebuild build \
  -project Cadence/Cadence.xcodeproj \
  -scheme Cadence \
  -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild build \
  -project Cadence/Cadence.xcodeproj \
  -scheme 'Cadence Watch App Watch App' \
  -destination 'generic/platform=watchOS' \
  CODE_SIGNING_ALLOWED=NO

make smoke
make watch-smoke
```

Add or update focused unit coverage for:

- Unified workout history ordering and isolation behavior.
- Health provider fakes and authorization/read/write calls from their owning
  actor.
- Typed WatchConnectivity message and settings parsing, including malformed or
  missing values.
- Watch timer/delegate callbacks updating state only after entering the main
  actor.
- Cardio configuration Sendable snapshots.
- Volume-guidance range conversion preserving existing coach thresholds and
  recommendation copy.
- Warning-classifier rejection, normalization, and exception matching.

Acceptance requires all of the following:

- Every SwiftPM and Xcode target is compiled in Swift 6 language mode with
  complete strict-concurrency checking.
- The full SwiftPM suite and both existing smoke suites pass.
- Clean Debug simulator builds and the Release archive succeed for the embedded
  iOS/watch product.
- Build logs contain zero owned warnings.
- Every remaining warning matches a reviewed, exact toolchain exception; the
  anticipated AppIntents metadata message is not exempted unless it still occurs
  in the final clean build.
- Searches find no unexplained `@unchecked Sendable`, `nonisolated(unsafe)`,
  `MainActor.assumeIsolated`, or first-party `@preconcurrency` use.
- CI `core-tests` and `testflight-build` both pass on `main` before the migration
  is considered shipped.

## Rollback

Because the migration is source/build-configuration-only and has no persistence
schema change, rollback is the single migration commit. If a production-only
toolchain issue appears, revert the complete change rather than mixing Swift 5
and Swift 6 targets or disabling individual concurrency diagnostics.
