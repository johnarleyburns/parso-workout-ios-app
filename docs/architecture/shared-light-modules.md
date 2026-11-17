# Watch/widget and FIT portability extraction research

Research only; no production modules moved. Inspected the current Cadence package and shipped entry points, and sibling Tonearm/Voxglass manifests and Watch targets. This proposal is a dependency refactor, not a second Watch implementation.

## Conclusion

A smaller shared layer is viable. The highest-confidence sequence is: isolate Garmin portability, reduce widget dependencies to their existing value contracts, then split the shared workout runtime from phone-only features. Keep one implementation of logging, set defaults, volume accounting, HR policy and offline generation. A new `CoreLight` module that imports today's entire Core/Features graph would provide an API facade but no meaningful build reduction.

Preserve the existing `CadenceCore` module for persistent model declarations while slimming it. It avoids coupling this performance work to a model-module relocation. Also preserve the defining module of `WorkoutLiveActivityAttributes` (`CadenceFeatures`) unless a separate upgrade/migration plan explicitly handles existing Live Activities. The source itself warns that ActivityKit depends on module-qualified type identity.

The practical “Core/Features Light” can therefore be the **existing module names with narrower contents**, plus newly extracted higher-level modules. It need not literally introduce duplicate Light types.

## Current graph and code evidence

```text
phone app ── Core + Features + Fixtures + ExerciseImages
Watch app ── Core + Features
phone widget ── Features ── Core
Watch widget ── Features ── Core

Features ── Core ── CadencePlanning
                 ├─ FreeExerciseDBPlusPlus
                 └─ FreeExerciseDBPlusPlusFIT ── FITSwiftSDK ── OrderedCollections
```

- `CadenceCore/Package.swift`: Core directly depends on both DB++ products; Features depends on Core unconditionally. Widget linking Features therefore reaches all Core dependencies.
- `Cadence/Cadence.xcodeproj/project.pbxproj`: Watch links Core and Features; both widget targets link Features.
- `../parso-tonearm/project.yml`, `TonearmWatch` and WatchWidgets: use `TonearmWatchProtocol` / `TonearmWatchCore`, not broad TonearmCore. Its Package.swift has actual narrow targets.
- `../parso-voxglass/project.yml`, `VoxglassWatch`: similarly uses `VoxglassWatchProtocol` / `VoxglassWatchCore`.
- Important difference: these music Watch layers do not prove Cladiron can remove all local domain/coaching/persistence code. Cladiron intentionally executes workouts offline and has a local SwiftData history.

## What widgets really need

`CadenceWidgets/CadenceWidgets.swift` and `CadenceWatchWidgets/CadenceWatchWidgets.swift` already use projections rather than opening SwiftData or HealthKit:

- From `CadenceFeatures/PlatformSnapshot.swift`: `CadenceTodaySnapshot`, `CadenceWeeklyMuscleSnapshot`, `CadencePlatformSnapshotStore`, `CadencePlatformRequestStore`, `CadenceWatchWidgetState`, `CadenceWatchWidgetStore`, `CadenceWatchActiveWorkout`, `CadenceWatchComplicationState`.
- From `WorkoutLiveActivityAttributes.swift`: the one shared ActivityKit contract and ContentState (iOS only).
- From `Format.swift`: phone widget uses only `duration` and `distance`, but the same enum also contains methods accepting `SetEntry`, `MeasurementUnitPreference` and `WorkoutMath`.
- `PlatformSnapshot.swift` refers to `ThisWeekDestination`. Its raw enum in `WeeklyDetailSelection.swift` is bundled with conversions accepting `WeekRing.Kind` and returning `WeeklyDetailMode`.

Move/split at symbol boundaries: keep the Foundation-only contract and formatting declarations in a tiny defining module. Put `Format`'s model-dependent methods in extensions in the shared workout feature target. Keep ThisWeekDestination raw cases in the contract layer; its WeekRing/dashboard conversions belong in an extension above that layer. This is one enum and one formatting implementation, with extensions rather than copies.

Do not copy Swift files into multiple Xcode target source phases. That recompiles separate module-qualified types, grows maintenance divergence and is especially dangerous for the ActivityKit attributes.

To retain ActivityKit identity without carrying heavy Features forever, progressively make **CadenceFeatures the small platform-contract module**, moving other Features implementations to `CadenceWorkoutFeatures` (shared) and `CadencePhoneFeatures` (phone only). Consumers change explicit imports. If a new `CadencePlatformContracts` name is preferred instead, preserve the old ActivityKit declaration until a deliberate Live Activity upgrade strategy is tested; otherwise the widget step is not yet independent of old Features.

## FIT portability: two different paths

1. `CadenceCore/GarminFITBridge.swift` is the only file importing `FreeExerciseDBPlusPlusFIT`. It uses `GarminFITAdapter` for lossless completed-strength export/import with DB++ ACTUAL sidecars. Its callers are phone-only `Cadence/.../Settings/GarminFITViews.swift` and the strength summary export button. **This is the first extraction.**
2. `CadenceCore/FITExport.swift` is a separate Foundation-only cardio FIT codec. `DataExport.decodeAny`, `encodeFIT`, `decodeFIT`, `isFIT` call it. It does not import Garmin's SDK. Moving just GarminFITBridge removes the expensive SDK dependency without first moving JSON backup/import APIs.

Suggested first target:

```text
CadencePortability ── CadenceCore + FreeExerciseDBPlusPlusFIT
phone app ── CadencePortability
Watch/widgets ── no CadencePortability dependency
```

Use `git mv` to move the bridge's implementation; remove DB++FIT from Core's manifest dependencies; add portability to the phone target and dedicated bridge test target. Existing internal `TrainingEngineBridge.workout(from:plans:)` and `timestampString` are currently inaccessible across modules. Use a narrowly scoped `package` API in the same Swift package rather than copying their mapping or indiscriminately making all internals public. Apple/Swift documents package access for exactly this intermodule boundary: [Swift access control](https://docs.swift.org/latest/documentation/the-swift-programming-language/accesscontrol/).

For a later complete portability extraction, Core cannot continue calling `FITExport`/`DataExport` after those move above it. Separate backup value DTOs from codec dispatch; keep DTO definitions below both persistence and portability, and move file-format sniffing/dispatch upward. Avoid `Core -> Portability -> Core` cycles. Do not create separate strength/cardio JSON serializers to work around them.

## Watch requirements that must remain shared

- `WatchStrengthFlowModel.swift` is an observable SwiftData-backed runtime and calls WorkoutRepository for exercise creation, partner identity, set entry, deletions and history. Move it to shared workout runtime, not a copied Watch fork.
- `WatchSetDefaultSnapshot` / persistence / `PerformerSetPlanner` / `PartnerPlanResolver` provide exact previous-set defaults and performer isolation.
- `WatchHeartRateReceiver`, durable outbox/completion helpers, HRSampling and cardio intensity policies preserve idempotent HR transfer and local history. Widget snapshots do not replace these.
- `WatchHomeSuggestedStrengthView` first resolves a valid phone suggestion, then assembles a persisted `WatchSingleExerciseSuggestionContext`, and can generate locally from `ExerciseLibrary.starter` when absent. `WatchSingleExerciseSuggestionAssembler` credits active sets via shared VolumeCredit and feeds the shared generator. Removing generation/catalog/DB++ wholesale would change offline behavior.
- Keep common generator/policy code in a shared `CadenceCoaching` target consumed by phone and Watch. Remove phone-only dashboard, backup, assessment presentation and full plan editing from the Watch graph. Base DB++ may still be required; Garmin FIT must not be.
- Current model methods call VolumeCredit, CardioMinuteAccumulator and WorkoutMath. VolumeCredit in turn uses `TrainingEngineBridge.setCredits`. Slimming Core therefore needs a foundational catalog/credit adapter, with advanced engine/generation methods extracted above Core; simply moving the entire bridge upward causes a dependency cycle.

## Persistent identity and synchronization constraints

The code differs from older README wording: `Store.swift` explicitly makes the Watch local-only, with the phone the sole CloudKit writer. Watch data moves over WatchConnectivity, not shared private CloudKit mirroring. `watchSchema` is the complete shared-model schema plus `WatchCardioHistoryRecord`.

Keep `@Model` definitions in CadenceCore initially, as well as existing schema membership, IDs, store URLs, relationship semantics and CloudKit configuration. Preserve schemaVersion 3, legacy default.store support and split Local.store/Sync.store behavior. A smaller Watch dependency graph does not require removing schema types from existing Watch stores. Shrinking that schema or moving models between defining modules is a separate migration-risk task, not an assumed free import change.

Apple explains the role of schemas, containers and migration plans, but does not promise arbitrary model-module moves are safe. Treat that uncertainty explicitly and require upgrade tests on copied old stores before considering it. [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer), [SwiftData schema migration](https://developer.apple.com/videos/play/wwdc2025/291/).

## Proposed final graph

```text
CadencePlanning                         (existing Foundation planning primitives)
CadenceCore                             (same model identity; shared domain/math/store kernel)
CadenceFeatures                         (small platform contracts; existing ActivityKit identity)
CadenceCoaching -> Core + Planning + base DB++
CadenceWorkoutFeatures -> Core + Features + Coaching
CadencePhoneFeatures -> WorkoutFeatures + Coaching
CadencePortability -> Core + DB++FIT     (canonical mapping API shared, never copied)

phone -> PhoneFeatures + WorkoutFeatures + Portability
Watch -> WorkoutFeatures + Coaching
widgets -> Features only
```

`CadenceCoaching` remains on Watch deliberately. Narrowing it further should follow measured symbol reachability and offline acceptance, not “Watch needs no engine” assumptions. A dedicated `CadenceWatchProtocol` can be added later if transport DTOs become a substantial independent unit; start with real boundaries, not many empty facade targets.

SwiftPM targets are modules; library products expose target APIs. Declaring a Light product with the old heavy target does not remove its transitive compilation. [SwiftPM targets/products](https://docs.swift.org/latest/documentation/packagemanagerdocs/introducingpackages/).

## Phased delivery and evidence

1. **Garmin bridge extraction**: no persistent-schema changes. Preserve exact sidecar, duplicate keep/replace/cancel/undo, size ceilings, malformed-file errors, canonical plan reference and owner-only set rules. Existing Garmin bridge tests must move with the code and pass; generic phone and Watch builds must show no FITSwiftSDK task for Watch. Full iPhone archive retains SDK as needed.
2. **Widget contract extraction / thinning Features**: golden decode/encode old app-group snapshots and commands; preserve suite/key strings and stale-marker rules; one ActivityKit attributes declaration; test Live Activity start/update, lock-screen actions, complication deep link and smart-stack rest ring. Build widget targets and verify the graph contains no SwiftData/DB++/Garmin.
3. **Shared workout runtime versus phone features**: move one implementation per symbol; make actor boundaries/package access explicit. Keep storage in original Core module. Verify phone/Watch set-default parity, partner separation, paused/recovered workout behavior, completed HR chart and durable WC completion reconciliation.
4. **Coaching/catalog isolation and optional backup extraction**: preserve offline Watch suggestion parity, canonical exercise IDs/aliases/exclusions, cited rationale and 20-muscle volume arithmetic. Benchmark cold and incremental phone/Watch/widget builds before/after with compiler task summaries.

Acceptance must include same toolchain/runner/configuration baseline measurements, target/dependency assertions (not just binary dead stripping), full Swift 6 checks, existing store-upgrade fixtures, and device checks with phone unavailable. No advertised speedup until measured. No model duplication, copied policy functions, hard-coded replacement credit weights, duplicate ACTUAL mapper or second set-default resolver is acceptable.
