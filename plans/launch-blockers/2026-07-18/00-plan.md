# Launch-blocker field-testing fixes — research + phased plan

## Context

Field testing surfaced seven launch blockers during/after a phone strength workout:

1. **Screen auto-locked mid-workout** (idle timer was supposed to be disabled).
2. **Lock/unlock kicked the user to Home** with a "Resume" card; expected to still be in the workout.
3. **The workout ENDED with no user input** after a second ~2-min lock (no alert was ever shown).
4. **Finished workout missing from Home's daily history** (coach saw it; History page showed it).
5. **Swap exercise in workout edit is a silent no-op** (add works; swap picks then does nothing).
6. **Set weight auto-fill ignores rep count** — should use per-exercise, per-rep-count, per-performer history.
7. **Tap latency** — set rows, weight/reps/RPE fields, and Home "Your Plan" feel clunky; must be instantaneous.

Constraints: logic provably fast via headless `swift test`; views simple-by-construction; XCUITest smoke suite stays frozen (≤12); no schema changes needed anywhere in this plan.

## Decisions (settled with user 2026-07-18)

- **A workout must NEVER be ended/cancelled by the system — only an explicit user tap ends it.** Auto-**pause** is acceptable (idle watchdog, crash recovery); auto-end is not.
- **Crash/upgrade safety:** if the app crashes, is killed, or is upgraded mid-workout, the workout must survive. On next launch: adopt it **paused** and show the **"Resume Workout" card** on Home (do NOT auto-present the workout screen). The dead gap must not count as elapsed time.
- **Home daily history:** true today-list from a direct query (not coach facts).
- **Autofill fallback:** exact rep-count match → **e1RM estimate (cited)** → existing cascade.

## Root causes (verified, file:line)

### Issues 1–3 — Session lifecycle
- **Keep-awake** (`Shared/KeepAwake.swift:8-29`) sets `isIdleTimerDisabled` only via view onAppear/onDisappear on SessionView (`SessionView.swift:493`). It re-enables lock whenever SessionView leaves the screen even mid-workout; pre-workout HR gate/countdown overlays (`HomeView.swift:497-518`) aren't covered; no scenePhase re-assertion.
- **Pop-to-Home on lock:** SessionView is a NavigationStack push (`HomeView.swift:282, 315, 940-954`) on in-memory `@State path` (`:24`). Process stayed alive (Resume card at `:291, 839-859` is gated on in-memory `active.strengthSession`), so this matches the known iOS 17 NavigationStack pop-on-background with non-Codable (SwiftData) path values. Nothing auto-pauses — "paused" was the Resume card's implication; the wall-clock `WorkoutClock` kept running.
- **Auto-end:** the idle watchdog (`SessionView.swift:57-68, 579-588, 1296-1317`; `autoEndOnIdle` default TRUE, 10 min) counts time since the last **logged set** — `poke()` only at `:524, :534, :584, :1416, :1593`; typing/tapping never counts. The "Still training?" alert can arm unnoticed (e.g. as the phone locks), and its **30s auto-end deadline is wall-clock**, so it expires during the lock → `endWorkout()` fires on the first 5s tick after unlock, before the user sees anything. Verified no other no-input end path exists (watch relay only streams BPM, `AppModel.swift:280`; editing a past session has no end control, `SessionView.swift:405-424`).
- **No relaunch reconstruction:** `ActiveWorkoutModel` is fresh at launch (`CadenceApp.swift:11`); an in-progress session (`endedAt == nil`) is never re-adopted.
- **Defense gap:** `AppModel.handleWatchEndSession` (`AppModel.swift:268-285`) stamps `endedAt` on any watch-sent session id, no guard for the phone's active session.

### Issue 4 — Home daily history
Home's "What you did" (`HomeView.swift:298, 728-768`) renders coach facts capped at ONE most-recent strength + cardio within 72h (`CoachDecision.swift:266-296`, `CoachFacts.swift:233-240`; completed ⇔ `endedAt != nil`, `TrainingEvent.swift:154-157`) — it is structurally not a daily list, and it lags the coach snapshot. History uses a plain `@Query` + `HistoryPresenter` (`HistoryView.swift:19,30`), hence shows everything.

### Issue 5 — Swap exercise
`ExercisePickerView.swift:262-267` calls `dismiss()` **before** `onPick(picked)`; both swap sheets use custom `isPresented` bindings whose setters nil the backing state (`SessionView.swift:505-507`, `:518-520`), and the pick closures guard on that now-nil state (`:509`, `:522`) → silent no-op. Add works (uses the parameter). Robust in-repo pattern: `WorkoutPlanEditor.swift:217-224` (`.sheet(item:)`). Repo write-backs are correct and tested.

### Issue 6 — Autofill
Weight cascade (`SessionView.swift:210-221`): lastSessionWeight (any reps) → `WorkoutRepository.firstWorkingSetWeight` (`:523-529`, any reps) → `prescribedLoadKg`. No per-rep structure; reps side already has the pattern to mirror (`repLadderHistory` `:538-550`). `SetEntry` (`Models.swift:424-457`) has weight/reps/isWarmup/performedBy — derivable, no schema change. Performer scoping already threaded everywhere.

### Issue 7 — Tap latency (ranked)
1. **Keystroke → full 1660-LOC body re-eval + synchronous SwiftData scans per render.** `inlineWeight/inlineReps/inlineRPE` are `@State` on root SessionView (`:31-36`; fields `:1148/:1158/:1201`). Every rebuild re-runs `lastTimeSets` + `currentPR` per card (`:942-945`, per partner `:952`), `isAllTimePR` per set (`:1040→:1060-1069`), `wouldBePR` per keystroke (`:1119-1121`) — uncached scans (`WorkoutRepository.swift:507-518, 555-577`).
2. **`AnyView(ScrollView { VStack })`** (`:429-431`) + non-lazy ForEach (`:387-389`).
3. **On-tap synchronous fetches** in `openInlineEditor` (`:187-235`) before focusing.
4. **"Your Plan"** destination rebuilds `CoachFacts.make(from: buildTrainingEvents())` over ALL history on push (`HomeView.swift:350-358`) instead of reusing cached `coachSnapshot.facts` (`:64`).

Proven in-repo fix pattern: `HomeCoachModel.snapshot` + `Equatable Signature` + `.task(id:)` (`HomeCoachModel.swift:18/62/88`, `HomeView.swift:566-567`).

---

# Implementation plan (one branch + PR per phase)

Stacking: `phase-1-lifecycle` (off main) ← `phase-2-session-perf` ← `phase-3-swap-fix` ← `phase-4-weight-autofill`. `phase-5-today-list` is independent, off `main`, can run in parallel.

Phase 1 lands before the perf refactor because it stops data loss, its SessionView diff is surgical (delete watchdog, change end/present semantics) and rebases cleanly into Phase 2's structural rewrite, and it defines the activity-callback contract Phase 2's extracted editor must honor.

**Step 0 (per CLAUDE.md methodology):** copy this plan into `plans/launch-blockers/2026-07-18/` and keep `current_state.md` updated per phase.

## Phase 1 — Session lifecycle: never lose a workout

**1a. Idle watchdog redesign** — new `CadenceCore/Sources/CadenceFeatures/IdleWatchdog.swift`:
```swift
public struct IdleWatchdog: Equatable {
    public enum State: Equatable { case idle, prompting(since: Date), autoPaused }
    public mutating func recordActivity(now: Date = Date())   // any tap/keystroke/log/foreground; clears prompt/autoPause
    public enum TickResult: Equatable { case none, showPrompt, autoPause }
    // NO end case — auto-end is UNREPRESENTABLE by this type. Ignoring the prompt
    // (30s grace) yields .autoPause: the clock pauses, the workout is preserved.
    public mutating func tick(now: Date, timeoutMinutes: Int, isPaused: Bool, enabled: Bool) -> TickResult
}
```
SessionView: delete `lastActivity/idlePromptShown/idlePromptAt/checkIdle()/poke()` (`:57-68, 579-588, 1296-1317`). Alert: "Keep going"→`recordActivity`, "Save now"→`endWorkout()` (the explicit tap), any other dismissal→`recordActivity`; copy becomes "No activity for N min. Your workout will pause — it never ends on its own." On `.autoPause` → `active.pause(origin: .auto)` + visible "Paused" state in the control bar. `ActiveWorkoutModel` gains `pauseOrigin` (`.manual` / `.auto`): `recordActivity` auto-**resumes** only an `.auto` pause — a manual pause stays until the user resumes. Activity sources: root `.simultaneousGesture(TapGesture())`, all former poke sites, `onChange` of the inline fields, and `scenePhase == .active`.

**1b. Presentation — fullScreenCover at RootTabView, not a poppable push.** Extend `ActiveWorkoutModel` with an `ActiveSurface` enum (`.session(sessionID:)` / `.summary(...)`, Identifiable), `present()`, `minimize()` (the only way to Home mid-workout — new chevron-down toolbar button), and `adopt(_ session:, lastAlive: Date?)` (crash/upgrade recovery — see 1e). New pure `ActiveSessionRecovery.candidate(in:)` → most recent `endedAt == nil && deletedAt == nil && !isLogged`.
- `RootTabView.swift`: one `fullScreenCover(item:)` on `active.presentedSurface`; `.session` wraps `NavigationStack { SessionView }`; `.summary` shows `WorkoutSummaryView` (surface identity swap = no Home flash). Add relaunch reconstruction in `.task`.
- `HomeView.swift`: `launch()` drops `path.append(s)` (`:940-954`); Resume card calls `active.present()`; remove the finished-summary cover (moves to RootTabView). Keep `navigationDestination(for: WorkoutSession.self)` for history edits.
- `SessionView.endWorkout()`: active case no longer `dismiss()`es — surface flips to `.summary` (keep the Task-yield before setting `finishedSummary`).

**1e. Crash/upgrade recovery — a workout is NEVER lost.** All sets/session data are already durably in SwiftData (each `addSet` saves); what dies with the process is the in-memory `ActiveWorkoutModel` + clock. New `WorkoutHeartbeat` (CadenceFeatures, UserDefaults-backed — no schema change): `{sessionID, lastAlive: Date, pausedElapsed…}` written on the existing 5s session tick and on scenePhase transitions; cleared on explicit end/discard. On launch (`RootTabView.task`): if `ActiveSessionRecovery.candidate` matches the heartbeat's sessionID (or exists without one), `active.adopt(session, lastAlive:)` — the clock **folds [lastAlive, now] in as a paused span** (WorkoutClock is a pure value type; reconstruct with the dead gap excluded from elapsed), the session is adopted **paused (`pauseOrigin: .auto`)** and **NOT auto-presented**: Home shows the existing "Resume Workout" card (`home.resume`), and tapping it presents the cover and resumes. This covers crash, jetsam, force-quit, AND app upgrade (same relaunch path). Auto-end on recovery is forbidden — a stale week-old session still shows the Resume card (user may end or delete it explicitly from the session screen).

**1c. Keep-awake — state-driven.** New `IdleTimerArbiter` (reference-counted tokens, pure; app maps union → `isIdleTimerDisabled`). Rewrite `KeepAwake.swift` to route through it + re-assert on `scenePhase == .active`. Holders: SessionView (`!isManualLog`), **RootTabView on `active.isActive && !(active.isPaused && active.presentedSurface == nil)`** (covers minimized/any nav state, but a paused-and-minimized workout — e.g. crash-recovered on Home — does not burn the screen), `PreWorkoutHRView`, `PreWorkoutCountdownView`, warm-up `GuidedPhaseOverlay`.

**1d. Watch guard.** `WatchSessionEndPolicy.shouldApplyEnd(sessionID:phoneActiveID:)` in CadenceFeatures; `handleWatchEndSession` drops end messages for the phone's live session.

**Tests (CadenceFeaturesTests):** `IdleWatchdogTests` — promptAppearsAfterTimeout, **ignoredPromptAutoPausesNeverEnds** (30s past prompt → `.autoPause`; ticks at 10min/24h after that → `.none`; no end case exists to fire), anyActivityResetsAndClearsPrompt, activityResumesAutoPauseButNotManualPause, foregroundingCountsAsActivity, pausedNeverPrompts, disabledNeverPrompts. `ActiveWorkoutModelTests` — startPresentsCover, minimizeKeepsSessionActive, endFlipsSurfaceToSummary, summaryDismissClearsSurface, pauseOriginDistinguishesAutoFromManual. `ActiveSessionRecoveryTests` — picksMostRecentUnfinished, ignoresEndedDeletedAndLogged, **adoptFoldsDeadGapAsPausedSpan** (elapsed excludes [lastAlive, now]), adoptStartsPausedNotPresented, staleSessionStillRecoverable (a week-old candidate is adopted, never discarded). `WorkoutHeartbeatTests` — writeReadRoundTrip, clearedOnEnd, mismatchedSessionIgnored. `IdleTimerArbiterTests` — unionOfHolders, lastReleaseRestores, reassertMatchesHolders. `WatchSessionEndPolicyTests` — dropsEndForPhoneActiveSession, appliesEndForOtherSessions.

**Acceptance:** screen never auto-locks across HR gate → countdown → warm-up → session → cool-down → minimized-with-active-workout; lock/unlock returns to the session screen; NO code path ends a workout except explicit taps (Save now / End / cool-down finish / delete) — idle and crash paths can only pause; kill/upgrade mid-workout → relaunch shows the Resume Workout card, tap resumes with all sets intact and dead time excluded from the clock. Smoke tests may be **edited** for the push→cover change (count stays ≤12; preserve `home.resume`, `session.*` identifiers). SessionView + HomeView LOC shrink.

## Phase 2 — SessionView tap latency, provably fast

**New CadenceFeatures `SessionRenderModel.swift`** (+ `SessionHistoryCache`): an `Equatable Signature` (sessionID, setCount, latest set update, exercise order, roster, PR rule, formula — **keystroke state structurally absent**); `build(...)` produces per-exercise `ExerciseContext` (owner + partner lastTime, PR, `priorSamples`, firstWorkingWeightKg) and precomputed `prSetIDs`; `State.wouldBePR(...)` checks against cached samples per keystroke — no repo scan. `SessionHistoryCache` is an `@Observable` memo wrapper with a countable `rebuildCount` and `refresh(signature:build:)` that no-ops on equal signatures.

**View restructuring** (each new file <400 LOC; SessionView shrinks toward ~1,000, ratchet lowered in `scripts/check-test-pyramid.sh`):
1. **`InlineSetEditorView.swift`** — owns weight/reps/RPE/bodyweight/performer as *local* `@State`+`@FocusState`; input `InlineEditorConfig` value (prefill draft, roster, hint, `wouldBePR` closure); callbacks `onSave(SetDraft)/onDelete/onCancel/onActivity`. Keystrokes invalidate only this child.
2. **`ExerciseCardView.swift`** — one card taking its `ExerciseContext` + rows as values; `contextLine`/set rows/menus move here; PR badge = `prSetIDs.contains(set.id)`. Split `SetRowMenu.swift` if it nears 400 LOC.
3. Replace `AnyView(ScrollView{VStack})` with `some View` + `ScrollView { LazyVStack }`.
4. `openInlineEditor`: prefill from `cache.state`, no repo fetches on tap.
5. Rebuild via `.task(id: SessionRenderModel.signature(...)) { cache.refresh(...) }`.
6. **HomeView "Your Plan"** (`:350-358`): use `coachSnapshot.facts` instead of rebuilding CoachFacts on push.

**Tests:** `signatureIgnoresKeystrokeState` (N keystrokes → N equal signatures); **`equalSignatureNeverRebuilds`** (`refresh` ×50 → `rebuildCount` stays at 1) — the recompute-count proof; `loggingASetRebuildsExactlyOnce`; `settingsChangeRebuilds`; golden parity vs repository on a fixture store — `lastTimeParityWithRepository`, `currentPRParity`, `isAllTimePRParity`, `wouldBePRParity`, `partnerContextsSeparated`.

**Acceptance:** unit tests prove keystrokes → 0 history rescans and set-log → exactly 1 rebuild; no `AnyView`; lazy card list; editor state isolated (verifiable by reading the diff); device sanity check: typing has no per-keystroke jank, "Your Plan" pushes instantly.

## Phase 3 — Swap-exercise fix

**New CadenceFeatures `ExerciseSwap.swift`:** `Intent` (`.swapPlanned(oldName:)` / `.changeLogged(oldExerciseID:oldName:)`, Identifiable) and pure `outcome(intent:pickedExerciseID:pickedName:) -> Outcome` (`.renamePlanned` / `.moveSets` / `.noOp`), plus `renamedPlannedNames` (de-dupe mirroring `WorkoutRepository.changeExercise`).

**Views:** SessionView drops `swappingPlannedName`/`changingExerciseFor` + both custom bindings (`:504-528`) for one `@State swapIntent: ExerciseSwap.Intent?` + one `.sheet(item:)` whose closure reads the **captured item** (the WorkoutPlanEditor pattern); apply maps outcomes to planned-name write / `WorkoutRepository.changeExercise`. Also reorder `ExercisePickerView.swift:262-267` to `onPick(picked); dismiss()` (matching its own `:225-228`).

**Tests:** `ExerciseSwapTests` — swapPlannedRenames, swapPlannedToExistingNameDedupes, swapToSameNameIsNoOp, changeLoggedMovesSets, changeToSameExerciseIsNoOp, intentIdentityDistinguishesFlows.

**Acceptance:** both flows mutate on pick via detail page AND row tap; add flow unchanged; picker LOC ≤ its 532 ratchet.

## Phase 4 — Per-rep-count weight auto-fill + e1RM fallback

**New CadenceCore `WeightSuggestion.swift`:** `suggest(targetReps:history:formula:) -> Result?` where `Result` = `weightKg` (raw entered kg — preserves dumbbell/barbell semantics), `basis` (`.exactRepMatch` / `.estimatedFromE1RM`), `citationIds` (non-empty for e1RM: reuse existing **`oneRMEstimation`** registry id — verified present). Inverse formulas: Epley `w = e1RM/(1 + r/30)`; Brzycki `w = e1RM × (1.0278 − 0.0278r)` via `settings.formula`. Rules: most-recent exact-rep set wins → e1RM from most recent best working set → nil (view falls through to existing cascade).

**New accessor** `WorkoutRepository.performerSetHistory(for:performedBy:excluding:)` (mirrors `repLadderHistory` `:538-550`): raw-weight, non-warmup, per-performer, newest first. Confirm `SetSample` carries raw weight+reps+date (add a raw-weight init path if it only has effective load — still no schema change).

**Cascade integration** (extend `SessionViewModel` or new `InlineEditorDefaults.swift`): `defaultWeight(targetReps:currentSessionSets:performerID:priorHistory:formula:prescribedKg:isPrescribed:)`; precedence current-session-exact-rep → `WeightSuggestion` → existing cascade. Feed via Phase 2's `InlineEditorConfig` (`ExerciseContext.priorSamples`, per performer — no fetch on tap). Changing reps before touching weight re-computes the prefill.

**Citation hard rule:** update `oneRMEstimation` usage note + `docs/CITATIONS.md` entry for the new surface; hint UI in `InlineSetEditorView` replaces `inlinePriorWeightHint` (`SessionView.swift:41`, rendered `:1261-1266`): exact match → "Last time at N reps: X"; e1RM → "Suggested from your best recent set" + `CitationLink(compact: true)`. Test `everyEmittedCitationIdResolves` fails the build if the id leaves the registry.

**Tests:** exactRepMatchWins, mostRecentExactMatchPreferred, e1RMScalesFromBestRecentSet (numeric inverse-Epley), e1RMUsesChosenFormula, warmupsExcluded, **partnerHistoryFullySeparated**, roundTripSelfConsistency, noHistoryReturnsNil; cascade: currentSessionExactRepBeatsPrior, fallsThroughToPrescribedLoad, unitConversionViaCanonicalKgRoundTrips; repo: performerSetHistoryFiltersWarmupsAndPerformer (in-memory container).

**Acceptance:** 8-rep row prefills last 8-rep weight for that performer; only-5-rep history prefills the inverse-Epley estimate **with a visible tappable citation**; empty history behaves exactly as today.

## Phase 5 — Home "What you did" = true today-list (independent)

**New CadenceFeatures `TodayActivityPresenter.swift`** (pattern: `HistoryPresenter`): `entries(sessions:cardio:unit:now:calendar:) -> [Entry]` — same calendar day, strength completed ⇔ `endedAt != nil`, `deletedAt == nil`, active session auto-excluded (Resume card covers it), **no cap**, newest first; `Entry` carries kind/id/title/detail ("5 exercises · 18 sets")/value/completedAt.

**HomeView:** replace `whatYouDidFacts` (`:728-733`) with the presenter over the existing `@Query` arrays; row rendering (`:770-810`) keeps layout but takes `Entry`; tap routing by carried ids; empty copy "Nothing yet today." Coach pipeline and insight surfaces untouched (history display, not coaching output — no citations needed).

**Tests:** includesOnlyToday, inProgressExcluded, deletedExcluded, **multipleSameDayAllListed**, mixedStrengthCardioSortedNewestFirst, midnightBoundaryWithInjectedNow, formatsVolumeAndDurationPerUnit, emptyDayYieldsEmpty.

## Cross-cutting

- **LOC ratchet:** lower SessionView's ceiling (1745) each phase to its new size; new files <400 (Features and app target both).
- **Features import ban:** all new package types import only Foundation/SwiftData/Observation; semantic enums, no SwiftUI.
- **XCUITest freeze:** edit existing smoke steps only (Phase 1's cover change); never add tests; preserve accessibility identifiers through the Phase 2 extraction.
- **Schema:** zero model changes anywhere.
- Per CLAUDE.md: each phase → `swift test` + `xcodebuild`, update `current_state.md`, conventional commit with Co-Authored-By trailer, PR referencing spec IDs (FR-1, field-testing §02/§04).

## Verification (end-to-end, per phase and at the end)

1. `cd CadenceCore && swift test` — all new suites green (the perf proofs are the `SessionHistoryCache`/signature tests).
2. `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build` + the frozen smoke suite (restart CoreSimulator if launches balloon).
3. On-device field script: start a workout → lock the phone 3× (short + >10 min) → each unlock returns to the live session, screen never auto-locks, nothing ends (at worst the workout is auto-paused with a visible Paused state); force-kill mid-workout → relaunch shows the Resume Workout card → tap resumes with sets intact and the dead gap excluded from elapsed; finish → workout appears on Home today-list immediately; edit → swap exercise via detail page and via row; add sets at 12/10/8/6 reps and confirm per-rep prefill (+ citation link on estimated ones); typing and "Your Plan" feel instant.
