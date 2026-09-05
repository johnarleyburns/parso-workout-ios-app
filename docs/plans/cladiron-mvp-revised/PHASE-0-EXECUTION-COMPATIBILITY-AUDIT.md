# Phase 0 execution-compatibility audit

Updated: 2026-09-05
Scope: v2.5 §§7–10, §§39–42, §47.0, `WS-EXECUTION-COMPAT`, Appendix AA

This is a repository-backed closure map, not a replacement product plan. “Verified
shipped” means the implementation and a focused test are present in this tree.
Device-only gates remain called out even when the code seam is shipped.

## Phase 0 requirement matrix

| Requirement | Status | Repository evidence / exact gap |
|---|---|---|
| One DB++ import boundary, pinned at 1.15.4 | **verified shipped** | `CadenceCore/Package.swift` pins `exact: "1.15.4"`; [`TrainingEngineBridge.swift`](../../../CadenceCore/Sources/CadenceCore/TrainingEngineBridge.swift:1) is the boundary; [`check-engine-boundary.sh`](../../../scripts/check-engine-boundary.sh:7) enforces it; `TrainingEngineContractTests` and `ExerciseDatabaseTests` cover the contract. |
| 873 built-in exercises and the 20-muscle DB++ ontology | **verified shipped** | `ExerciseDatabaseTests` asserts 873 records and 20 canonical muscles; [`MuscleGroup.swift`](../../../CadenceCore/Sources/CadenceCore/MuscleGroup.swift:14) keeps the raw DB++ keys. |
| Package evidence resolves into app citations | **verified shipped** | `TrainingEngineBridge` exposes package evidence as app-facing values; `CitationIntegrityTests`, `ExerciseEvidenceTests`, and `TrainingEngineContractTests` cover resolution. |
| SwiftData local store and private iCloud mirroring | **verified shipped (code) / device gate open** | [`Store.swift`](../../../CadenceCore/Sources/CadenceCore/Store.swift:4) declares the shared schema and `.private(...)` CloudKit configuration; `WorkoutRepositoryTests` cover persistence and round trips. A two-device private-CloudKit run still requires real iPhone/iPad verification. |
| Legacy GRDB/SQLite replacement | **superseded by v2.5** | §7.2 explicitly adopts the shipped SwiftData/private-CloudKit architecture; no second persistence stack should be introduced. |
| Existing iPhone plan materializer | **verified shipped** | [`EditablePlan.apply`](../../../CadenceCore/Sources/CadenceFeatures/EditablePlan.swift:86) writes every exercise's per-set prescription and legacy fields; `EditablePlanTests` covers mixed exercise counts, weights, provenance, and partner plans. |
| Collapsed strength cards and full-screen set editor | **verified shipped** | [`SessionRenderModel.swift`](../../../CadenceCore/Sources/CadenceFeatures/SessionRenderModel.swift:382) builds performer-aware pending rows; `SessionRenderModelTests`, `SessionViewModelTests`, and the iPhone Train views cover the collapsed → editor seam. |
| Performer-specific history/default precedence | **verified shipped** | [`PerformerSetPlanner.swift`](../../../CadenceCore/Sources/CadenceFeatures/PerformerSetPlanner.swift:107) documents and implements precedence; `PerformerSetPlannerTests`, `EditablePlanTests`, and `SessionRenderModelTests` cover owner/partner isolation. |
| Stable partner alternation and out-of-order continuation | **verified shipped** | [`SetAlternation.swift`](../../../CadenceCore/Sources/CadenceFeatures/SetAlternation.swift:12) is the shared interleave; `SetAlternationTests`, `SessionRenderModelTests`, and `WatchStrengthFlowModelTests` cover rotation. |
| 20-muscle direct/indirect/stabilizer/eligibility credits | **verified shipped** | [`VolumeCredit.swift`](../../../CadenceCore/Sources/CadenceCore/VolumeCredit.swift:1), `VolumeCreditTests`, `ExerciseDatabaseTests`, and `TrainingFactsVolumeTests` cover 1.0/0.5/0.0, eligibility, and canonical keys. |
| Watch strength lifecycle and durable phone reconciliation | **verified shipped (headless) / device gate open** | `WatchStrengthFlowModel` plus Watch views implement start/log/rest/cooldown/summary/cancel; `WatchStrengthFlowModelTests`, `WatchStrengthSyncApplierTests`, `WatchResumableSessionTests`, and `AppModelWCSessionDelegateTests` cover stable IDs, replay, discard, and phone application. Real unreachable-phone execution remains mandatory. |
| Watch cardio lifecycle and exactly-once completion merge | **verified shipped (headless) / device gate open** | `WatchWorkoutManager`, `WatchCardioModels`, and `WatchCardioCompletion` are the current seams; `WatchCardioCompletionTests`, `WorkoutRepositoryTests`, and Watch UI tests cover duplicate/relaunch-friendly envelopes and HealthKit merge. Live HR/haptics/HealthKit still require hardware. |
| JSON export/import and legacy decoding | **verified shipped** | [`DataExport.swift`](../../../CadenceCore/Sources/CadenceCore/DataExport.swift:115) keeps optional metadata; `DataExportTests`, `WorkoutRepositoryTests`, and `ExportFreezeFixTests` cover old/new round trips. |
| Unified `Plan → Week → Day → Session → Item → Set` value model | **partial → additive envelope + coach producer landed** | `UnifiedPlanModel.swift` supplies the Codable value graph; [`UnifiedPlanStore.swift`](../../../CadenceCore/Sources/CadenceCore/UnifiedPlanStore.swift:1) persists validated plans through an additive SwiftData envelope with stable IDs and deterministic LWW upsert; `WeeklyPlanUnifiedBridge` now converts the shipped coach week into the seven-day graph and Home persists it. A normalized per-entity mapping and client relationship persistence remain open. |
| Rich per-set intent and source identity into the live session | **partial → adapter + iPhone/coach producer slices landed** | `PlannedSetPrescription` now carries optional source set ID, load mode, `%1RM`, RPE, rest, and warm-up; `WorkoutSession` carries optional `planSessionID`; `RuntimePrescriptionAdapterTests`, `EditablePlanTests`, and `WeeklyPlanUnifiedBridgeTests` prove resolution, stable IDs, all item-family conversion, and legacy fields. The editable iPhone start path and Home's generated coach-week path now convert through unified sessions; normalized plan provenance, sharing integration, and device smoke remain open. |
| Snapshot `%1RM` at send/start and keep it fixed | **partial** | The pure adapter resolves and rounds `%1RM` once from `AthleteExecutionSnapshot`, and tests prove missing-e1RM rejection. A trainer send/preflight path and immutable shared-zone snapshot do not exist yet. |
| Unified plan into existing Watch strength inputs | **partial → versioned payload + coach producer landed** | [`WatchPlanPayload.swift`](../../../CadenceCore/Sources/CadenceCore/WatchPlanPayload.swift:1) carries rich per-set prescriptions with legacy names/ladder fallback; `WatchStrengthView` and `WatchStrengthFlowModel` consume it, and `WatchStrengthSyncApplierTests` cover phone reconciliation. Home now builds that payload from `WeeklyPlanUnifiedBridge` sessions; the real plan-origin device smoke gate remains open. |
| Unified plan into existing Watch cardio configuration | **partial → versioned payload + coach producer landed** | `WatchPlanPayload.Cardio` carries kind, duration, distance, target zone, and interval data; `WatchSync.TodayPlan` round-trips it and planned-cardio launch passes duration/zone into `WorkoutConfigurationSpec`. Home now builds planned cardio from the same unified coach sessions; the real planned-cardio device gate remains open. |
| Trainer private-device convergence | **partial → value-level contract landed** | [`ClientShareStore.swift`](../../../CadenceCore/Sources/CadenceCore/ClientShareStore.swift:1) and `ClientShareStoreTests` prove two trainer-device connections converge with last-writer-wins metadata; persisted SwiftData draft stamps and a visible conflict notice remain open. |
| Trainer↔client CloudKit sharing (`CKShare`, custom zone, change tokens) | **partial → production adapter landed / device gate open** | [`CloudKitClientShareStore.swift`](../../../CadenceCore/Sources/CadenceCore/CloudKitClientShareStore.swift:1) creates per-client custom zones/`CKShare`s, returns the saved invitation URL, accepts invitations, writes plan/result records with revision/sentAt preservation and deterministic last-writer-wins, and consumes zone change tokens. `InMemoryClientShareStore` remains the deterministic contract fixture; real two-Apple-ID invite/accept, shared-zone permissions, and phone integration remain open. |
| Phone is the sole Watch→CloudKit bridge | **verified shipped (code)** | [`Store.swift`](../../../CadenceCore/Sources/CadenceCore/Store.swift:4) documents the boundary; Watch uses local-only storage and WatchConnectivity; `AppModel` and `WatchStrengthSyncApplier` apply on the phone. |
| No runtime network path | **verified shipped** | `check-no-network.sh` is the repository guardrail; the DB++ catalog/evidence are bundled and `TrainingEngineBridge` uses the pinned package. |
| Swift 6 strict concurrency / warning-free package baseline | **verified shipped (package baseline)** | `Package.swift` sets Swift language mode v6 for all targets; the package build completed for the adapter slice. Full `make ci` remains the release gate. |

## Appendix AA fixture closure

The existing fixture coverage is frozen by the following focused tests before
planner UI work. The new adapter suite extends, rather than forks, this set.

| Appendix AA.7 fixture | Current fixture(s) | Status |
|---|---|---|
| Two exercises, distinct set counts/reps/loads | `EditablePlanTests.testApplyPreservesEachExerciseSetLadderAndWeight`; `RuntimePrescriptionAdapterTests.testLegacyPlanFieldsArePopulatedAlongsideRichPrescriptions` | **verified shipped** |
| Legacy session without rich prescriptions | `EditablePlanTests.testLegacySessionWithoutPerformerDataResolvesToTheOwnerPlan`; `WorkoutRepositoryTests.testExportImportRoundTrip` | **verified shipped** |
| Collapsed card → pending row → editor → save → history | `SessionRenderModelTests`; `SessionViewModelTests`; `WorkoutRepositoryTests` set/history cases | **verified shipped (headless)** |
| Two partners, separate histories and rotation | `EditablePlanTests` performer round trips; `PerformerSetPlannerTests`; `SetAlternationTests`; `WatchStrengthFlowModelTests` partner cases | **verified shipped (headless)** |
| Swap before/after logging | `ExerciseSwapTests`; `StrengthEditingTests` | **verified shipped** |
| All 20 muscles and credit exclusions | `ExerciseDatabaseTests`; `VolumeCreditTests`; `TrainingFactsVolumeTests` | **verified shipped** |
| Watch strength payloads, replay, cancel, resume, cooldown | `WatchStrengthFlowModelTests`; `WatchStrengthSyncApplierTests`; `WatchResumableSessionTests`; `AppModelWCSessionDelegateTests` | **verified shipped (headless)** |
| Cardio duplicate/relaunch and HR-present/absent summaries | `WatchCardioCompletionTests`; `WorkoutRepositoryTests`; `WatchCardioSummaryPresenterTests` | **verified shipped (headless)** |
| JSON export/import and old fixture decoding | `DataExportTests`; `ExportFreezeFixTests`; `WorkoutRepositoryTests` | **verified shipped** |
| Single iPhone/Watch plan → runtime → history smoke path | Existing iPhone/Watch smoke tests cover manual/runtime flows; rich payload materialization, Watch launch, phone reconciliation, duplicate/out-of-order result handling, and source-ID export/import are now headless-tested, but no plan-origin device smoke path exists yet | **partial** |

## Dependency-ordered closure map

1. **Complete the unified domain value model** around the landed session
   snapshots: add `Plan`, `PlanWeek`, `PlanDay`, session/item identity, provenance,
   and scheduling as Codable value types; keep SwiftData mapping out of the
   execution adapter until invariants and fixture serialization are stable.
   **Value model, additive persistence envelope, and coach producer landed
   2026-09-05:** `UnifiedPlanModel` plus `PersistedPlan`/`UnifiedPlanStore`
   round-trip and converge through stable IDs; `WeeklyPlanUnifiedBridge` makes
   the existing coach week a validated seven-day `Plan`, and normalized entity
   mapping remains open.
2. **Promote the adapter to a single materializer entry point** used by the
   existing iPhone start path. **Landed 2026-09-05:** `PlanSessionSnapshot(session:)`,
   `RuntimePrescriptionAdapter.materialize(planSession: Session, ...)`, and
   `WorkoutRepository.startSession(from: Session, ...)` now share one conversion
   path; focused tests prove source-ID/load preservation and repository creation.
   Keep `EditablePlan.apply` as the compatibility path until the UI plan producer
   and migration coverage prove equivalent output. **Landed 2026-09-05:** the
   editable iPhone start path now calls `EditablePlan.unifiedSession()` and the
   unified repository overload, with a regression test for set identity, resolved
   load intent, RIR, and exercise-key mapping; partner/provenance fields are
   applied after materialization for compatibility.
3. **Add versioned Watch plan payloads** for rich strength prescriptions and
   planned cardio, with legacy fields retained and unknown keys ignored. Extend
   the existing Watch views/flow rather than creating a planner runner.
   **Landed 2026-09-04:** `WatchPlanPayload`, Today Plan transport, Watch
   strength launch/reconciliation, and the planned-cardio configuration seam.
4. **Add append-only/reconciliation contract fixtures** for old/new payloads,
   duplicate/out-of-order events, and export/import of source IDs. Then run the
   real iPhone + Watch gates.
   **Landed 2026-09-05:** Watch compatibility/replay fixtures, source-ID export
   round trip, and append-only result assertions.
5. **Only after execution compatibility is green**, add the CloudKit sharing
   protocol and its in-memory contract, then the production custom-zone/
   participant implementation and real two-Apple-ID invite/accept test.
   **Contract and adapter landed 2026-09-05:** `ClientShareStore`,
   `InMemoryClientShareStore`, and `CloudKitClientShareStore` cover the
   value-level protocol and production record-zone seam. The real Apple-ID
   device gate and phone integration remain mandatory.

Out of scope for this closure slice: planner UI, compact set-stack authoring,
trainer UI, external-client packets, entitlement gating, Mac shell work, and any
replacement runtime or exercise database.
