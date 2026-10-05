# Current Status

Updated: 2026-10-04

## Latest implementation — Muscle map: untracked muscle is white, never red (2026-10-04)

Field report: with every muscle group green, the Home muscle map still showed
red on the head, hands and feet, and on the neck/splenius, tibialis anterior and
rhomboid area. The artwork is drawn red and the map only coloured masks of
groups in the current volume scope, so the artwork's red showed through (1) on
anatomy no group covers (head, hands, feet) and (2) on groups outside the scope
(neck, tibialis, rotator cuff, hip flexors are not in `defaultTracked`).

- `scripts/generate-muscle-masks.py` also writes one `MuscleMask-<panel>-untracked`
  mask per panel: every muscle pixel no group claims (outline strokes excluded).
  The 30 tracked masks regenerate byte-identical.
- `MuscleMapLayout.neutralMaskAssetNames(for:visibleGroups:)` returns the
  untracked mask plus every mask group outside the volume scope;
  `HomeMuscleMapView` draws those solid white under the group colours.
- `MuscleMapMaskAssetTests` now checks every red artwork pixel anywhere on both
  panels (head, neck, hands and feet included) is covered by exactly one mask
  (a group's or the untracked one), the catalog holds the untracked masks, and
  the neutral list is exactly the untracked mask plus the hidden groups.

Renders (all groups on target): `/tmp/muscle-map/before-default-scope-*.png`
(43,783 / 62,641 red px) → `/tmp/muscle-map/after-default-scope-*.png` and
`after-all-groups-*.png` (0 red px).

## Latest implementation — Watch workout session left recording for 27 hours (2026-10-04)

Field report: the Watch showed a workout recording for 27 hours although the
watch workout had ended long before, and neither app showed an active or paused
workout. watchOS keeps an `HKWorkoutSession` alive across app relaunches. After
a relaunch, recovery reattached it with nothing on screen owning it, so nothing
ever ended it. Other paths that kept a session running: finishing a watch lift
and never tapping Done on its summary, discarding an unfinished lift from Today,
and a session whose saved metadata had been cleared (recovery skipped it).

- New pure `WatchSessionOwnership` (CadenceFeatures) decides whether the running
  session is owned: by a workout screen on show, by the iPhone workout that
  started it (up to 6 h), or by a resumable watch lift. An unowned session
  shows a "Still recording · End session" card on Today. One left more than
  4 h is ended automatically, and Today says so once ("Ended a forgotten
  session").
- Recovery always asks HealthKit for a running session (not only when our
  metadata flag is set), ends a stopped-but-not-ended one, and ends abandoned
  ones even on a background relaunch.
- `stopWorkout` ends the session even when the builder is gone or the manager's
  flags already say idle.
- A watch lift stops recording when its summary appears; discarding an
  unfinished lift from Today also ends its session. Workout screens register as
  session owners (`ownsWatchWorkoutSession()`).
- `WatchSessionOwnershipTests` reproduces the 27-hour field case.

Verification: `swift test --parallel` 2058/2058 passed (see note below), watch
scheme generic build succeeded. Device check by the owner: start a watch
lift, finish it, leave the summary, relaunch; the workout indicator must be gone.

Dependency: DB++ moved to 1.17.1 (its released HealthInterop fix), and the
`patch-dbpp-healthinterop.sh` workaround was removed from the hook, Makefile,
`xcodebuild-safe.sh` and CI.

## Latest implementation — Muscle Map colours every tracked muscle completely (2026-10-02)

Field report: on the Home muscle map some muscles were not coloured at all and
others only partly. Audit of the 25 previous masks against the artwork (all
groups forced to "on target"): only ~76% of the torso/limb muscle fill was
coloured at all, and much of that by the wrong group. Front: forearms coloured the upper outer thigh instead of the
forearm; abdominals missed most of the rectus segments; biceps covered only the
upper arm's outer strip; quadriceps/adductors/abductors were horizontal bands
cut through the thigh; tibialis/calves were mixed up on the right leg; neck
covered one side. Back: mirrored seeds used x=0.5 while the back art's midline
is x=0.547, so traps, lats, mid back and lower back were lopsided bands; most
of both hamstrings, both calves except one gastrocnemius head and the right
forearm were uncoloured, and the right glute was coloured as abductors.

- `scripts/generate-muscle-masks.py` now segments by the artwork's own
  outlines: it labels the connected red regions, assigns each to a group from a
  hand-checked seed point (left and right halves seeded separately because one
  side is the superficial layer and the other the deep layer), splits the few
  shapes anatomy treats as two muscles (trapezius → neck/traps/mid back,
  TFL → IT-band/vastus lateralis, glute max/medius, lumbar erectors under the
  lats, medial triceps at the armpit), excludes head/hands/feet, floods
  linework and slivers from the nearest region, fills enclosed specks, and
  leaves the dark outline strokes uncoloured so the muscles stay legible.
- Five new masks colour muscles that are visible on a panel without having a
  callout there: front traps and triceps, back abdominals (obliques), back
  adductors (gracilis) and back quadriceps (vastus lateralis).
  `MuscleMapLayout.maskGroups(for:)` lists the masks per panel and
  `HomeMuscleMapView` draws masks from it (still filtered by the volume scope).
- Eleven callout anchors that sat off their muscle were moved onto it.
- `MuscleFocusThumbnail` used the front mask for every group, so back-only
  groups (glutes, hamstrings, lats, …) showed an empty thumbnail; it now uses
  `MuscleMapLayout.primaryPanel(for:)`.
- `MuscleMapMaskAssetTests` (swift test) fails if any `MuscleGroup` has no
  mask, a callout has no mask or sits off its muscle, a mask asset is missing,
  undersized or empty, any red muscle pixel of the torso/limbs is uncoloured,
  or two masks overlap.

Before/after renders: `/tmp/muscle-map/` (`before-*`, `after-*`).

## Latest implementation — field-test batch: Watch cardio/voice, This Week deep links, Total, muscle masks (2026-10-01)

A field-testing batch. Six fixes, all headlessly tested where logic exists:

- **Watch HIIT duration bug.** A phone-started strength workout opens the
  Watch's single `HKWorkoutSession` for live HR. Starting an 8-minute HIIT on
  the Watch mid-strength left `startWorkout` returning `false` without touching
  the shared `sessionStart`, so the HIIT completion borrowed the strength start
  and recorded 34 minutes. Cardio now has its own clock (`cardioSessionStart`),
  and the new pure `WatchCardioTiming` (CadenceFeatures) resolves the completion
  span from it; ending a layered cardio no longer tears down the strength
  session. `WatchCardioTimingTests` reproduces the 26+8 = 34-minute field bug.
- **Watch spoken cues silent.** Beeps (`workoutSounds`) played but speech
  (`spokenCues`, confirmed on) did not. `AVSpeechSynthesizer` now uses a
  system-managed session instead of sharing the bell player's repeatedly
  reconfigured session, the stop-before-speak race is removed, and the
  `workoutStarted` phrase no longer says "(trimmed)".
- **Progress question bar scroll reset.** The horizontal question picker now
  binds `.scrollPosition(id:)`, so selecting Tests (or any question) no longer
  snaps the bar back to the start.
- **Settings tab removed.** Today owns a top-right gear (`home.settings`) that
  pushes the same `HomeRoute.settings`; the bottom bar is Today/This Week/
  Progress/Search. UI test helpers updated.
- **Strength over time Total.** "Combined" is renamed "Total" and is now
  recomputed from only the currently charted lifts (pure
  `StrengthProgress.totalSeries(from:)`), not every lift with history. Persisted
  `"Combined"` selections migrate to `"Total"`.
- **This Week deep links.** Today's weekly rings now deep-link per ring — sets →
  muscle coverage, cardio minutes → Cardio, sessions → Strength — expanding the
  section and scrolling to it (`ThisWeekDestination`,
  `CadencePlatformRequestStore.requestThisWeekSection`, `ScrollViewReader`
  anchors).
- **Muscle-map mask audit.** The generator previously assigned each anchor to
  the nearest connected red component, so several muscles shared one region
  (forearms == abductors, adductors == quadriceps, glutes == abductors) and
  others landed on the wrong side. Rewritten as a geodesic watershed with blob
  seeding; all 25 masks now audit clean (no duplicates; every front/back side's
  centroid within 0.10 of its anchor).
- **Search Browse layout.** Browse/Recents/Popular moved into the List so it
  shares the rows' margins, and the browse-mode control plus chip rows are one
  row to remove the extra vertical gap.

Verification: full `swift test --parallel` package suite (2,043 tests) passes;
generic iPhone→embedded Watch build succeeds with signing disabled; all
repository guardrails pass (test-pyramid, design-tokens, localization, citations,
engine boundary, history safety, accessibility, Watch AppIcon/background modes,
xcodebuild platform, release safety). The Search Browse and This Week deep-link
changes are layout/behavioral and still want device visual confirmation.

## Latest implementation — field fixes and custom-lift Combined strength (2026-09-30)

The field-fix pass now keeps Today workout and summary routes inside their
own navigation root, disables the live-workout accessory when no session is
active, keeps the Done-for-today actions on one line, and uses “Do more”. The
This Week rings retain their captions while removing the redundant completed /
target ratio, and Cardio Minutes presents one Science row that opens all
citations together.

Muscle-map hit targets are 64pt with the artwork excluded from hit testing;
back masks were regenerated symmetrically. Watch workouts now have an opt-in
spoken-cue setting, route cues through the Watch audio session, announce
interval phases and boxing round numbers, and sync the preference from iPhone.
Strength Over Time Combined carries each lift’s latest known e1RM forward and
includes every custom charted lift, not only the powerlifting trio. The full
parallel package suite passes (2,015 tests). Generic app builds still encounter
the known Swift frontend IRGen crash in the pre-existing large Train compile
batch; the failure is not a source diagnostic from this pass.

## Latest implementation — award audit remediation (2026-09-30, pre-commit)

This pass implements the repository-owned award gaps identified in the latest
audit. Quick Talk now has a hold-to-talk path on the next uncompleted set,
SpeechAnalyzer-first transcription on iOS 26+, exact-command auto-save with an
Undo confirmation chip and eight-second follow-up window, an opt-in
raise-to-talk motion monitor, named entity-resolution/execution contracts, and
a bounded local Heard log with no audio persistence. Ambiguous speech still
opens review rather than mutating the workout. Partner rows use the same path.

Liquid Glass is now restricted to floating controls; content cards use plain
semantic surfaces. The iOS search tab, live-workout bottom accessory, search
zoom transition, sensory feedback, centered PR takeover, set-logged animation,
AHAP patterns, week-close moment, iPad Progress/Settings/session split roots,
muscle-map recommendation thumbnails, and compact “Why this workout” summary
are implemented. DB++ exercise-name localization now has a versioned sidecar,
launch-locale coverage tests/guardrails, and the new raise-to-talk preference is
portable with settings export/import.

The D1 app icon has shipped: the Fe-mark `AppIcon.icon` (Icon Composer
layered asset, brief in `docs/brand/app-icon-designer-brief.md`) is in the
project, and the stock coach cartoons are retired in favour of the muscle-map
thumbnails. The app UI ships in English, English (UK), German, Spanish, French,
Dutch, Portuguese (Brazil), Simplified Chinese and Traditional Chinese; all
non-English strings are `needs_review` until a native-speaker pass. Final device screenshots, preview
video, App Store Connect nomination fields, human translation review, and
real-device AX5/HealthKit/Watch validation remain release gates; this file does
not claim those external outcomes.

## Latest implementation — most-recent-workout recommendation exclusion (2026-09-30)

Today’s personalized strength recommendation now rebuilds a temporary exercise
exclusion set from the most recently completed workout, using completion time
and not a same-day filter. This prevents the immediately preceding workout’s
movements from being selected again while leaving the catalog and user history
unchanged. The policy is headless-tested for cross-day history, completion-time
ordering, normalization, and personalized substitution behavior.

## Latest implementation — regular-width dashboard and AX5 fallback (2026-09-30)

The C5 re-audit found the weekly dashboard had no runtime regular-width
adaptation even though the iOS target supports iPad. `AdaptiveSurfaceLayout`
now keeps the dashboard stacked on compact width and at accessibility Dynamic
Type sizes, while presenting its cards in a readable two-column grid on a
regular-width iPad. The decision is headless-tested in `CadenceFeatures`, and
the view remains system-color/token based for both light and dark mode. The
existing muscle-map List selector remains the single detailed muscle list;
the duplicate long list below “Fill the gaps” is not present.

## Latest implementation — C5 accessibility contract and rotor audit (2026-09-30)

The C5 re-audit found that the live workout had custom actions and
announcements, but no semantic set-row contract or VoiceOver rotors. The
pending and completed rows now use a headless `SetRowAccessibility` presenter
with partner-aware labels, wired Exercises and Unlogged sets rotors, and the
existing Log/Edit/Repeat/Delete actions. A fixed-layout accessibility ratchet
and device-only manual matrix are now part of the release evidence. Focused
tests, the full parallel package suite, all guardrails, and sequential
generic iPhone→Watch builds pass. The manual VoiceOver, Switch Control, AX5,
Reduce Motion/Transparency, and iPad checks remain device gates, as does the
Apple Developer provisioning update required by the new H5 CloudKit container.

## Latest implementation — award-plan audit and H5/C4/release closure (2026-09-30)

This working series audited the active award craft, award polish, and unified
release plans against the repository and closed the highest-risk repository-owned
gaps. H5 now has explicit local/sync SwiftData schemas, a separate private
CloudKit container identifier, a file-backed migration runner, rollback JSON
snapshot, count verification, 30-day legacy retention, and an explicit purge
guard. Backup & Restore exposes the migration only when Apple Health backup is
enabled; all supported HealthKit backfill jobs are queued durably before the
split-store readiness marker is written, and the app switches stores on the next
launch. C4 interval cues no longer use a PR haptic for work transitions, and PR
takeovers now present the new value, previous value, improvement, and rule.

The release story is now internally consistent about private iCloud backup,
with featuring-nomination and press-kit drafts under `docs/`. The localization
catalog and Xcode project now include the eight planned locale variants for the
core award strings, and the local package runner is explicitly parallel within
one invocation; iPhone and Watch builds remain sequential. New H5, split-schema,
PR-takeover, and existing FIT/HealthKit tests
remain headless and light/dark-safe; raw color growth remains below the token
ratchet.

Remaining release gates are intentionally explicit: native CloudKit Production
schema deployment, multi-device/HealthKit/Watch field validation, full native
translation review beyond the seeded core catalog, iPad AX5 review, and final
App Store Connect submission/featuring work. The repository does not claim those
external/device outcomes as complete.

## Active implementation — Full award roadmap

### Current audit task — H4 HealthKit restore and DB++ 1.17.0

H4 restore contracts are now implemented additively. Cladiron-authored Apple
Health workouts are source-filtered, decoded by schema/sync ID, conflict-planned
by the newest sync version, and restored into local history without replacing
partner sets. Legacy summary-only workouts remain idempotent and clearly marked
in their notes. Assessment restore now carries the complete recorded input set,
including weight, reps, exercise, notes, age, and sex. The onboarding welcome
screen and Transparency & Control both expose a safe repeatable Health restore.
HealthKit background delivery is enabled for workouts and VO2 samples after
authorization. DB++ is pinned to exactly 1.17.0, with the repository's
compatibility patch applied to both SwiftPM and custom Xcode derived-data
checkouts.

The remaining H-stream release work is intentionally not represented as done:
the two-configuration CloudKit/local store split and migration/purge (H5), a
dedicated count/progress Backup & Restore center (H6), anchored multi-device
delivery/device validation, and release/schema/privacy artifacts (H7) still
need implementation and real-device validation. Watch audio capture and the
eight-locale translation pass likewise remain open.

### Current audit task — H1 JSON v8 whole-database portability

H1 is now implemented locally as an additive JSON v8 native-store archive. It
registers and round-trips all 22 SwiftData entities, preserves the rows/scalars
not represented by the convenience DTOs, merges idempotently by stable ID, and
deduplicates legacy cardio HR/route samples whose old nested format had no
sample IDs. The coverage test seeds every entity, imports into a fresh store,
re-imports it, and compares decoded row payloads. The package suite (1,951
tests), guardrails, generic iPhone build, and standalone generic Watch build
now pass sequentially; the final commit, remote CI, and cache-cleanup results
are recorded in the handoff for this working series.

The same audit also closed the C6 onboarding shape gap in code: the first-run
flow is now four screens, health/location/age prompts stay contextual, and the
live session has a one-time first-set teaching overlay. The audit also closed
the remaining P4 entry points in code: the iOS 18 `AudioRecordingIntent` hands
off to the reviewed Quick Talk sheet, exercise entities opt into Spotlight
indexing, and the Live Activity opens the Today start route. Full P4 device
validation, L3 localization, signature choreography, iPad/device AX5 review,
and store-story/submission artifacts remain open in the audit below.

The user authorized implementing the complete award craft and award polish
roadmap. This pass productizes the core C1–C6 and P2/P3/P4/P5/P6 slices:
launch/icon cleanup, Today completion/duration behavior, semantic light/dark
colors, cue policy, accessibility actions/announcements, phone Quick Talk
voice logging, a typed Foundation Models fallback, locked Talk handoff,
Spotlight, Watch double-tap affordances, and AlarmKit rest-alert plumbing.
Existing partner logging, exact-weight, FIT/HealthKit, and sequential-build
changes remain preserved. The H2 cross-store reference layer is now additive
and tested, and H3 has its HealthKit metadata/sync-version contract plus
restore conflict policy. The durable outbox/reader, store migration, and
remaining device-only/release-artifact work are called out explicitly below.

## ACTIVE PLAN — Unified Cladiron release program (2026-09-28)

The single roadmap is `plans/cladiron-release/2026-09-28/00-unified-plan.md`
(paste-ready `HANDOFF.md` beside it). It interleaves three design sets:
award polish (P0–P7, L0–L3), award craft (C0–C7), and health backup (H0–H7:
your own workouts → Apple Health, non-health → a new iCloud container
`iCloud.guru.parso.cladiron.sync`, whole-DB JSON v8, tester migration,
restore on a new iPhone; this resolves Guideline 5.1.3(ii)). The sequence is
G0 gate, then steps 1–23 ending in release R. Decided: award-polish D1–D15,
award-craft D1–D9 (D8 = design for iPad), D10 direction → H stream. **Open:**
H1–H10, U1 (first-run shape vs award-polish D13), U2 (interim public
release?), U3 (sequential vs two lanes), award-polish D16. The repository now
contains the implemented app slices and guardrails; device/release-only
decisions remain documented for the release phase rather than being represented
as shipped runtime behavior.

## Latest implementation — Partner-aware set logging and field audit (2026-09-29)

The partner workout logging path now treats the first interleaved pending row as
the actionable row, so Quick Log appears for the next uncompleted partner set
instead of comparing a partner's local set index with the combined session
count. Repeat is performer-scoped: it copies the selected partner's most recent
set and never falls back to Me's set when that partner has not logged the
exercise yet. These behaviors have focused regression coverage.

Untouched direct weights now render blank rather than prefilled `0` (an explicit
zero remains visible), and exact historical loads are used as starting values
without plate rounding. Estimated loads may still use the existing fallback
rounding. The cardio hero no longer applies the dark translucent text treatment,
and the bottom session controls now have consistent vertical spacing.

The local workflow is documented and enforced as sequential for iPhone and Watch
builds, while SwiftPM tests run in parallel within one invocation, in `CLAUDE.md`
and the Makefile. The full SwiftPM suite passed
1,951 tests with zero failures; the focused SetAlternation suite now passes 16
tests. Generic iOS and Watch builds passed with signing disabled; and the
repository guardrails passed. Xcode still
reports the known deployment-target
warning (project target 27.0 versus the installed SDK's 26.5 maximum).

### Audio logging audit

Phone Quick Talk is now implemented: microphone and Speech framework capture,
the command grammar/parser, exercise/partner resolution, review-before-apply,
and live transcript UI are wired into the active strength session. The
implementation is intentionally opt-in and never silently logs an ambiguous
command. Permission copy is in `Cadence/Info.plist` and the settings/export
surface carries the voice preferences.

Watch audio capture remains open because it needs a separate watch microphone
UX and device validation. On iPhone, the iOS 18 locked-screen
`AudioRecordingIntent` now hands off to the same reviewed Quick Talk sheet as
the in-session hold gesture; Spotlight indexing and a Live Activity Today-start
route are also wired. Background-safe execution and device validation remain
release checks.

### Award-plan audit after latest pass

Closed in code: C1 launch/icon cleanup; C2 named accent palette and design-token
guardrail; C3 Today done state and duration estimator; C4 cue-policy tests plus
set/PR/rest VoiceOver announcements; C5 custom set/rest accessibility actions;
C6 four-screen onboarding and first-set coach mark; P2/P3a phone voice
capture/parser/resolver; P4 locked Talk handoff, Spotlight indexing, and Today
Live Activity route; P5 watchOS 11 target, double-tap primary actions, pure rest
planner, and AlarmKit adapter; P6 typed Foundation Models fallback with
fail-closed validation; plus the requested light/dark AccentColor variants.
The Live Activity renderer now has explicit high-contrast foreground content so
a black background cannot hide its values.

Still requiring implementation or real-device review: H4 anchored multi-device
delivery and Watch audio capture, H5–H7 store split/migration/Backup center/release work,
full P4 Live Activity button/Control Center validation, eight-locale UI/voice
localization (L3), full signature-moment choreography, iPad/device AX5
verification, and the store-story/submission artifacts. The Health outbox,
schema decoder, restore planner, local apply path, onboarding restore entry,
and Apple Health background-delivery registration are now runtime behavior.
The remaining store split, migration, dedicated Backup & Restore center,
anchored delivery, and release-only work are recorded explicitly rather than
marked complete without the corresponding runtime behavior.

Latest verification for this pass: the focused H4 decoder/planner/apply suites
passed; generic iPhone followed by standalone Watch builds passed sequentially
with signing disabled. The full final package/guardrail gate, follow-up commit,
push, remote CI check, and final cache cleanup remain for this working series.

## Latest implementation — Today row audit, DB++ 1.17.0, FIT, and HealthKit portability (2026-09-28)

The Today personalized recommendation row now tail-truncates long exercise
names so the sets × reps value stays on one line. The implementation was
audited against the active field-testing plan; no additional scoped Today
surface gap was found. The fix is pushed as `07054f5`, and its GitHub Actions
run passed both core tests and the TestFlight archive.

The working follow-up updates `free-exercise-db-plusplus` to exact `1.17.0`,
adds cardio FIT import/export (duration, distance, calories, HR, and GPS route
samples), and extends HealthKit ingest to include attached workout routes and
strength export HR samples. JSON remains the lossless full-app backup; FIT is
cardio/activity interchange only. A repeatable build-time compatibility patch
contains the tag's Swift 6/macOS `HealthInterop.swift` defects until upstream
ships the equivalent fix. FIT round-trip tests cover export/import, HR/GPS
samples, format sniffing, and CRC rejection.

The This Week Muscle coverage follow-up removes the duplicate long muscle-volume
row list below “Fill the gaps”; the map's List selector is now the detailed
muscle view. The map is 440pt tall with 48pt content-shaped muscle targets, and
selection uses a fresh identity so reopening the same muscle reliably presents
its detail sheet. HealthKit route import uses the attached workout route
series, and strength export includes recorded heart-rate samples.

The final three-pass audit also scopes HealthKit heart-rate imports to their
own workouts, requests route authorization, removes the workout-import cap,
and makes FIT imports deterministic and store-idempotent. The Xcode package
resolver now applies the DB++ compatibility patch to fresh and custom
DerivedData checkouts.

Verification for this slice: `make ci` passed 1,920 host tests and all
guardrails; a generic iOS build passed with code signing disabled. The local
build still reports the known iOS deployment-target warning (project target
27.0 versus the installed SDK's 26.5 maximum).

## Next planned work — Award craft (planned 2026-09-28, not started)

Design set written to `plans/award-craft/2026-09-28/`, complementing award polish.
It covers craft and identity only: 01 icon + launch (the current icon has text,
raster noise, and a watermark-like sparkle; remove the 2.4 s blocking `SplashView`),
02 color/type/illustration (empty AccentColor → system blue; 299 raw colors;
retire the stock coach cartoons for muscle-map thumbnails), 03 Today states
(new `doneToday`; replace the hard-coded `estimatedMinutes: 45` and the
fallback title with `WorkoutDurationEstimator`), 04 signature moments
(`CueKind` haptic vocabulary, set-logged animation, PR takeover; stacks on
award-polish P1), 05 AX5/VoiceOver depth + the iPad decision, 06 a 4-screen
first run, 07 store story + featuring nomination (folds into award-polish P7),
08 rollout C0–C7, a decision sheet (D1–D10), `HANDOFF.md`, and `mockups.html`
(B1–B16). No app code changed. **Release gate raised to C0:** Guideline
5.1.3(ii) (health data in iCloud, already flagged in the release audit) must
be resolved with App Review, or a fallback chosen, before any ADA path exists.
D1–D9 decided 2026-09-28; D10 became the health-backup stream. Superseded
as the next-task pointer by the unified plan above.

## Next planned work — Award polish (planned 2026-09-26, not started)

Design set written to `plans/award-polish/2026-09-26/` (overview, 01 glass &
navigation, 02 voice grammar, 03 voice capture/confirm UI, 04 Siri/Controls/
Live Activity/Spotlight, 05 Watch double tap + AlarmKit rest alerts, 06
optional on-device model fallback, 07 rollout, decision sheet, handoff
prompt, `mockups.html` with screens A1–A27 (private copy:
https://claude.ai/artifact/EkfyY6uNKhL4npdTRYkPg1), and `08-voice-battery-study.md`).
No app code changed. Decided 2026-09-27: D4 save immediately when sure; D6
Watch target → watchOS 11 (in P5); D8 Siri never logs in the background. Added
2026-09-27: **Quick Talk** phone voice logging (hold Log set / mic, opt-in
raise-to-talk, Action Button / Lock Screen Talk control via
`AudioRecordingIntent`, 8 s follow-up window). The battery study found
session-long continuous listening costs roughly 10–30× the mic/ASR runtime
(apps can't use Siri's low-power Always On Processor, and gym music defeats
silence gating), so it's opt-in and gated on on-device Power Profiler
measurement (D15). Also decided 2026-09-27: D12 hold Log set = Quick Talk; D13 raise-to-talk and
D15 always-listening are opt-in (offered in a new onboarding page and, while
unset, on the Get Ready countdown with "Never show again"); D14 lock-screen
Quick Talk saves clear commands only. All D1–D15 decided 2026-09-27 (see the
plan's `decisions.md`): D1 keep the Resume card for crash recovery, D2 search tab,
D5 partner nicknames, D9 AlarmKit opt-in, D10 Foundation Models fallback on by
default, D7 launch in en-US/en-GB/nl/es/pt-BR/fr/de/zh-Hans/zh-Hant for voice and
UI, with exercise-name translations added upstream to free-exercise-db-plusplus
as an additive i18n sidecar (`09-languages-and-localization.md`) and no
mainland-China storefront (no ICP filing). Mockups are now A1–A29.
**Immediate next task:** answer D16 (show machine-draft exercise-name
translations before native review), then run P0 (check the listed APIs against the iOS 27
SDK) and start P1 per `HANDOFF.md`.

## Active task — Cladiron visual redesign (2026-09-25)

Implementing the complete `CLADIRON_DESIGN_PLAN.md` presentation pass in one
working series, using `/Users/arley/Downloads/cladiron-mockups.html` as the
visual contract. The in-app browser is unavailable in this environment, so
visual verification is based on the mockup source, the pin acceptance table,
static checks, and the native iOS build; simulator execution remains disabled
by the repository rules unless explicitly requested.

Implemented and audited: shared visual tokens and native system tab shell;
Today hero, week rings, and action hierarchy; This Week heat-map/list surface;
live logging header/menu, medium/large set sheet, citations, PR moment/share,
and Live Activity rest layouts; Progress segmented charts/points/empty states;
widgets, iOS 18 Control Center control, onboarding copy, localization strings,
and accessibility labels. The presentation seams have headless coverage.

Verification: `swift test --package-path CadenceCore` passed with 1,912 tests;
generic iOS build passed; `make guardrails` passed; `git diff --check` passed.
Visual/device verification is intentionally deferred to the user. The anatomy
artwork now has generated per-muscle alpha masks derived from its supplied
red-fill regions and existing callout anchors, while the original silhouette
remains unchanged. The project now includes and embeds a watchOS 10 Smart Stack
widget target alongside the native Watch workout app.

## Latest gap-fix audit — 2026-09-25

The follow-up audit found and fixed three implementation gaps in the first
redesign pass:

- The active workout now populates Live Activity `nextExercise` after every
  logged set, so the rest state has both the countdown and the next movement.
- The Today/This Week widget now renders estimated minutes and muscle values
  instead of exposing literal placeholder expressions.
- Progress “Add” now creates a correctly named `Exercise plan` instead of a
  literal `(name) plan` title.

The current audit is clean for the implemented iPhone redesign surfaces. The
remaining plan-level constraints are unchanged and intentionally reported:
the bundled anatomy artwork is one raster image without safe per-region masks;
the project has no Watch Widget extension target for the requested Smart Stack
surface; onboarding still contains the existing preference/disclaimer flow in
addition to its privacy story; the new strings are only partially migrated to
`Localizable.xcstrings`; and AX5/screenshot verification could not be run
because simulator execution is disabled by repository guidance and the
in-app browser is unavailable. These require either new artwork/target
artifacts or an explicit device/simulator review pass.

Verification for this gap-fix pass: `swift test --package-path CadenceCore`
passed with 1,912 tests, the generic iOS build passed, `make guardrails`
passed, and `git diff --check` is clean.

## Latest full-plan audit — 2026-09-25

This follow-up closed the actionable Phase 6/7 gaps found after the previous
audit. Onboarding now presents the three short story pages from the plan
(`Free and open source`, `Private by design`, and `Coaching you can check`),
then presents the existing `HealthPrimingView` before preference capture.
The story strings are in the string catalog, and the new hero/session surfaces
use `ViewThatFits` fallbacks for compact Dynamic Type layouts.

The only remaining plan exceptions are the ones the plan itself requires us
to report rather than fabricate: the anatomy artwork is a single raster image
without safe per-muscle masks, and this Xcode project has no Watch Widget
extension target from which to ship a watchOS Smart Stack widget. A real
AX5/screenshot pass still needs a simulator or device; repository guidance
keeps that execution disabled and the in-app browser is unavailable.

Verification for this audit: `swift test --package-path CadenceCore` passed all
1,912 tests, the generic iOS build passed, `make guardrails` passed, and
`git diff --check` is clean.

## Latest follow-up audit — 2026-09-25

The source audit found and fixed four additional presentation gaps: completed
set rows now open the set sheet directly; the performer control is a native
Menu; weight increments remain a horizontal, non-truncating chip row and the
weight/reps steppers are secondary bordered controls; Progress lift rows now
show the matching chart-series color; and Start Workout/Pick Workout choices
use native bordered rows rather than custom card fills.

The same audit also found the Today hero was still using a hardcoded example
workout. It now previews the existing Personalized generator's value-only plan,
uses that plan's citation IDs, refreshes after history changes, and hands the
generated draft to the normal editor on Start or Edit without mutating data.

The remaining plan exceptions are unchanged: the anatomy asset is one raster
without safe per-muscle masks, the project has no Watch Widget extension target
for the Smart Stack requirement, and simulator/device AX5 and screenshot
verification is unavailable in this repository environment.

## Latest targeted gap fix — 2026-09-25

The targeted audit for the unavailable anatomy mask and missing widget target is
complete. The This Week anatomy map now overlays 25 deterministic, transparent
front/back muscle masks generated from the supplied artwork; each region is
tinted by its five-level heat value, and zero regions retain the dashed
attention target and VoiceOver control. The map also positions overlays and
targets inside the artwork's true aspect-fit rectangle instead of the full
container bounds.

The watch gap is closed with a native `CadenceWatchWidgets` watchOS 10 target,
embedded in the Watch app and restricted to `.accessoryRectangular`. It reads
the shared day snapshot for today's title and receives the Watch rest timer
projection for a live countdown during rests. The shared projection has a
round-trip/clear unit test, and the generator is retained at
`scripts/generate-muscle-masks.py` so the derived assets are reproducible.

The user will perform visual and device verification separately, as requested.

## Latest change — 2026-09-24: main-thread stalls and the Watch HR boundary

Branch `perf-main-thread-and-watch-hr`, delivered as a patch (not pushed).

- Watch Heart Rate Access boundary: it hung off a one-way UserDefaults flag,
  so after one tap on any build it never came back, even when HealthKit had
  never been asked. It now follows `HKHealthStore.statusForAuthorizationRequest`
  (`WatchHealthAuthorizationGate` in CadenceFeatures): shown first on every
  launch until the system sheet is answered, "Continue without heart rate"
  skips it for that launch only. The launcher's "Health access needed" row is
  refreshed from HealthKit at launch instead of staying stale.
- Watch cold launch: custom exercises replayed by WatchConnectivity on every
  activation were upserted on the main actor with one full-catalog fetch per
  exercise and an unconditional save. They are now fingerprinted (unchanged
  list = no work) and written once, serially, on a background context
  (`WatchCustomExerciseStore`). The root view queries only unfinished sessions
  instead of the whole log. WC activation and recovery run once per process.
- Catalog reconciliation (`seedStarterLibraryIfNeeded`) ran on every Watch
  launch and every iPhone foreground. `StarterLibraryReconciliation` runs it
  only when the build or the stored exercise rows (count + newest `updatedAt`)
  changed. iPhone store preparation runs once per process and decodes DB++ off
  the main actor first (`CatalogWarmup`), so the first UI lookup doesn't pay it.
- Workout screen: removed the whole-history `@Query` (it refetched every
  workout on each set save and re-rendered the screen). Weekly live volume now
  reads this week's sessions only, with credits memoized per exercise; rep
  patterns read the 21 newest sessions; recent partners the 60 newest.
  `VolumeCredit` set credits are read once.
- Previous-workout lists and the quick-start ranking no longer sort every set
  of every session (`WorkoutSession.hasSets`, cached ranking).

Verification: new tests in `StarterLibraryReconciliationTests`,
`BoundedSessionFetchTests`, `WatchCustomExerciseStoreTests`, and
`WatchHealthAuthorizationGateTests`. Only the SwiftData-free parts (gate,
fingerprint) were compiled and run (Linux Swift 6.1, language mode 6, no
warnings); `swift test`, the Xcode build, and a device run on iPhone + Watch
are still required. `check-test-pyramid`, `check-no-network`,
`check-engine-boundary`, `check-history-safety`, and
`check-xcodebuild-platform` pass; the macOS-only checks were not run.

## Latest audit — 2026-09-18

The implementation audit against the active field-testing plan found and fixed
one repository gap: the iPhone smoke contract still used the retired
`home.completed.showMore` identifier and skipped the new collapsed `My
History` → `View full history` interaction. It now asserts the current
`home.history.showMore` and `home.history.fullHistory` path.

Headless verification for this audit remains simulator-free. The local package
suite passed with 1,816 tests, the generic iOS build passed, and the updated
smoke contract is diff-clean and ready for the next release smoke run.

The previously open CloudKit schema gap is resolved: the additive
`ExerciseSuggestionExclusion` record type is now deployed to Production.
`make guardrails` passes its live Development/Production comparison.

The subsequent re-audit found and fixed the remaining architecture gaps:
This Week now owns a dedicated local navigation path, history destinations
carry stable IDs instead of live SwiftData models, missing history records
resolve to a recoverable unavailable state, and the glass dock uses shared
metrics for both compact geometry and root safe-area clearance. Home route
diagnostics remain DEBUG-only and contain no workout or health data. The Home
dashboard route builder was split so every source file remains within the
400-line guardrail.

Re-audit verification is green: 1,819 package tests, generic iOS build,
`make guardrails`, and `git diff --check`. No simulator or device was run;
the audit fixes are currently uncommitted for review.

The latest route audit also removed the remaining live SwiftData model from a
navigation path: Exercise Picker now routes by exercise UUID and resolves the
catalog record at the destination, with a recoverable unavailable state.

Background research: `Workout for You` currently generates a strength-only
`WorkoutPlan`. Cardio suggestion can reuse the existing `CardioWorkout`,
`CardioType`, indoor/outdoor, interval, HR, Watch, and `TimerCardioSetup`
surfaces, but needs a new value-only cardio suggestion contract, a modality
choice before generation, cardio-specific scoring from duration/intensity/type
history, and a cardio preview/start handoff. No cardio-suggestion code has
been implemented in this audit pass.

## Active task — field-testing UI simplification implementation

The field-testing UI plan and its follow-up plan are implemented and audited.
Today now uses a
single My Workouts queue plus bottom My History, This Week has an embedded
locally-bundled front/back anatomy map and independent Strength/Cardio/Volume
disclosures, scheduling preserves local date and time, Start Workout has the
three-column recent-cardio picker with Elliptical/Stair Climber, Progress is
summary-first, Settings is a glass-dock tab, and the transient automatic
loading labels are removed from Today. The old Today More route is retired.

The anatomy mockup remains a review artifact in `~/Downloads`; all comparison
filenames now show only selected Option A, with a self-contained portrait
front-left/back-right map, status-colored tappable regions, and a muscle
history detail surface. It no longer references `file://` resources.

The selected Option A interaction is now implemented in This Week: the locally
bundled source image is cropped into aspect-preserving front/left and back/right
panels, each mapped region uses the current weekly status color, and tapping a
region opens that muscle's direct/indirect exercise history with sets, reps, and
loads sorted direct-first then alphabetically. Watch application-context writes
now leave the main actor before the WatchConnectivity IPC call, so an explicit
sync toast does not freeze Today while the paired Watch is being updated.

The audit follow-up also made Coach Insights and About the Coach reachable from
Settings, corrected Transparency & Control copy that still referred to the
retired weekly Plan tab, removed the unused CloudKit root-toast view, and moved
Home's historical activity/muscle projection to a background SwiftData context.
The follow-up audit also moved scheduled-workout payload decoding and recent
cardio-choice derivation into that cached background projection, so the Home
render path only receives lightweight rows and identifiers.
CloudKit import completion/failure is now retained as a Settings-only status;
Home still receives no automatic restore toast or transient loading row.
The final audit also centralized weekly Cardio Minutes formatting in a tested
presentation seam, added smoke assertions for source-code leakage and GPS text
in the compact picker, and corrected repository guidance so commit hooks run
SwiftPM tests only while simulator smoke remains an explicit release gate.

Verification constraint for this pass: use headless Swift package tests and
static/build checks only; do not run simulator flows while the owner reviews
the anatomy mockups.

Verification so far:

- Full `CadenceCore` test suite is green: 1,819 tests, 0 failures.
- Native iOS generic-device build is green with signing disabled; this compiled
  the iPhone, Watch, widget, and package targets without launching a simulator.
- All repository guardrails are green, including test-pyramid, no-network,
  citations, engine boundary, history safety, live CloudKit schema parity, and
  Watch AppIcon checks.
- The final audit covers the follow-up plan's navigation, scheduling, anatomy-map,
  disclosure, cardio-picker, loading-label, and Home render-path requirements.
  Scheduled rows and recent cardio choices are now cached projections rather
  than per-render payload work. No known plan gap remains in this pass.
- The Option A mockup variants are self-contained, UTF-8 encoded, and contain
  no `file://` image references or external Lucide request. Their region detail
  interaction sorts direct work before indirect work and then by exercise name.
- `git diff --check` is clean.

## Repository reconciliation — 2026-09-17

The previous release baseline (`51e8210`) is present on `main` and synchronized
with `origin/main`: the scheduled-workout/Plan-removal implementation and the
scientific cardio-intensity implementation are already in the repository. This
resolution pass keeps those slices intact, fixes the deterministic personalized
history-index signature, aligns the three manual test documents with the
retired weekly-planning UI, and expands smoke coverage for Personalized
Workout scheduling. No simulator is part of this pass.

The scheduling API now rejects dates before the user's current local day and
owns rescheduling as an atomic lifecycle operation. Rescheduling clears a
stale started-session link and returns the item to `scheduled`; focused tests
cover past-date rejection and that transition. The UI preserves the selected
local date and time in the app-internal schedule and does not request EventKit
access.

## Active task — remove weekly planning; add individual scheduled workouts

The implementation target is now a single-workout workflow. Remove the
permanent Plan tab and retire weekly coach-plan creation from the user-facing
product. Preserve legacy weekly-plan SwiftData records and compatibility types
so existing private iCloud data is not destroyed.

### Product contract

- Today, Progress, and Settings remain the top-level tabs; Tests is reachable
  from Progress and Plan is removed.
- Personalized Workout and Custom Workout remain the primary planning flows.
- Workout Plan View gets a `Schedule this Workout` button immediately below
  `Start Workout`, using the same button size and style family.
- Scheduling stores an exact snapshot of the reviewed workout, including
  exercises, notes, sets, reps, fractional historical weights, load modes,
  warm-up/cool-down, and partner prescriptions.
- Scheduling is app-internal date scheduling. Do not request EventKit access or
  create an Apple Calendar event in this task.
- After a successful save, the date sheet and Workout Plan close and Home is
  shown.
- Home gets one `My Workouts` queue combining completed workouts and today’s
  scheduled workouts. Its `Show More…` action opens the planned-workouts list
  for today and future dates, with overdue uncompleted items still recoverable
  in the full view.
- Starting a scheduled workout uses the normal live-workout path. Completed
  scheduled items leave Planned Workouts and appear in completed history.
- No DB++ schema change is required: schedule dates and execution lifecycle are
  app-owned private-user state.

### Persistence contract

Add an additive CloudKit-compatible `ScheduledWorkout` SwiftData model with:
`id`, normalized `scheduledDate`, semantic `scheduledDayKey`, timezone ID,
title, versioned payload data, payload version, scheduled/started/completed/
cancelled status, optional started-session ID, created/updated dates,
`deletedAt`, and `originDevice`. Use tombstones, not destructive deletion.
Add it to `CadenceStore.schema` and both CloudKit schema guardrail maps.
Keep `PersistedPlan` and normalized weekly-plan models in the schema, but stop
creating or displaying new weekly coach plans.

The scheduled payload is a versioned Codable app-side snapshot. It is not a
mutable reference to a generated plan. Existing Workout Plan edits must be
captured at the moment the user taps Save.

### Weekly-planning removal

Remove `Tab.plan`, `PlanningView`, weekly-plan generation/editing affordances,
`Generate with Coach`, `Describe a plan`, `New blank week`, weekly-plan routes,
and weekly-plan onboarding copy. Retain coach facts, insights, readiness,
training preferences, citations, and Personalized Workout inputs where still
needed. Old `cladiron://plan` and Handoff links must safely route Home rather
than expose a dead route.

### Schedule UI and lifecycle

Add a local date-and-time schedule sheet with today/future validation, explicit
Save and Cancel, persistence error handling, and a visible confirmation. Thread an
`onSchedule` callback through the suggested and custom Workout Plan routes; the
root Home route performs the final navigation reset after persistence succeeds.
Do not create a `WorkoutSession` merely by scheduling. On start, copy the exact
payload into a session, link it with `scheduledWorkoutID`, and mark the schedule
started. Mark it completed only when the workout actually ends. Reschedule,
start-now, delete, crash recovery, and duplicate same-day schedules must all be
explicit and deterministic.

### Performance work required in this task

- Move Home coach value extraction (`TrainingFacts`, events, engine history,
  custom-volume extraction) off the main actor using a SwiftData model actor or
  background value-snapshot worker; only publish the final immutable snapshot on
  MainActor.
- Move Watch settings/custom-exercise payload construction off the main actor.
- Cache and hash Watch payloads; coalesce repeated foreground/settings sends and
  skip unchanged `updateApplicationContext` calls.
- Keep CloudKit event handlers tiny and debounce import bursts. Refresh Home only
  when a relevant workout/cardio/scheduled-workout signature changes; do not
  rebuild the coach for every imported entity or notification.
- Move bulk HealthKit ingestion/save work off the main SwiftData context.
- Add signposts around coach extraction, Home projections, HealthKit ingestion,
  Watch payload construction/transmission, and CloudKit import handling.

### Acceptance requirements

Core tests must cover payload round-trip, fractional weights, reps, partners,
timezone/DST date semantics, today/future/overdue filtering, tombstones,
duplicate same-day schedules, and start/complete/abandon/delete lifecycle.
Smoke tests must prove there is no Plan tab, no weekly coach-generation action,
both Personalized and Custom Workout Plan screens expose equal-sized Start and
Schedule buttons, scheduling returns Home, Planned Workouts renders today and
future entries, and starting a scheduled workout preserves its exact plan.
No simulator is part of this implementation pass. Commit with `--no-verify`
only after code and focused verification are complete, then push.

### Implementation completed in this pass

- Added `ScheduledWorkout` as an additive app-owned SwiftData/CloudKit model,
  including versioned exact-plan payloads, fractional loads, partner plans,
  tombstones, date-only timezone semantics, and linked session lifecycle.
- Added Schedule Workout UI below Start Workout, Home Planned Workouts today and
  future/overdue views, rescheduling, deletion, start/resume routing, and return
  to Home after save. The former Plan tab and unreachable weekly authoring views
  are removed; legacy weekly records remain in the schema.
- Removed automatic weekly coach-plan projection to Watch/widgets. Watch payload
  construction is detached, fingerprinted, and coalesced; Home coach extraction
  and HealthKit ingestion use background SwiftData contexts. CloudKit import,
  coach, Home projection, HealthKit, and Watch payload signposts are present.
- Added headless scheduled-workout payload/presenter/lifecycle/schema coverage
  and updated smoke/screenshot contracts to assert Plan is absent, both
  Personalized and Custom Workout scheduling is available, and a scheduled
  Personalized payload can be reopened with its exercise intact. No simulator
  was run.
- Replaced JSON-encoder-dependent history signatures with an ordered scalar
  representation so identical SwiftData history cannot spuriously rebuild the
  Personalized exercise index. The full package test gate is required before
  this resolution is considered release-ready.

## Roadmap position — implementation aligned; Phase 2 hardware close-out pending

Phase 3 implementation is complete for the active single-user workout slice;
the former weekly-plan depth/review UI is intentionally superseded by the
single-workout redesign.
The remaining Phase 2 work is field validation on real iPhone/Watch hardware
and same-user private iCloud convergence; those checks are documented in
`PHASE_2_MANUAL_TEST.md` and are intentionally not replaced by simulator runs.
Phase 3's human field checklist is in `PHASE_3_MANUAL_TEST.md`; the Phase 4
platform checklist is in `PHASE_4_MANUAL_TEST.md`.

### Completed

- **Phase 0 — foundations:** persistence, CloudKit schema and sync contracts,
  Watch payload boundary, and guardrails are complete.
- **Phase 1 — athlete implementation:** manual workout authoring, mixed-session
  boundaries, Watch projection, and the combined cardio/mobility runner are
  implemented. The earlier weekly-plan authoring surface is retained only as
  compatibility/core history, not as a current tab.
- **Phase 2 code slice:** unified plan authoring/execution support, stale
  exercise-substitute protection, indexed/faceted exercise search, and normal
  descending planner rep ladders are implemented and covered by tests.
- **Phase 3:** the core coach-depth contracts remain available for compatibility,
  while the former weekly-plan depth/review UI is retired. Current user-facing
  depth is Personalized/Custom Workout authoring, exercise exclusion/search,
  substitution, volume/history, autoregulation cues, and explicit Supporter
  contribution. The optional $9.99 contribution is the only StoreKit product;
  a successful purchase displays the Home Supporter badge without gating any
  feature.
- **Phase 4 implementation:** `BoundedPlanningRequestParser` remains a bounded,
  deterministic, tested core compatibility capability, but its former Plan-tab
  review UI is intentionally retired with weekly planning. The current
  user-facing Phase 4 surfaces are readiness, transparency/control, WidgetKit,
  App Shortcuts, Handoff, offline behavior, larger-surface delivery, and
  accessibility/performance polish.
  The optional readiness check-in is user-facing on Home. App Shortcuts,
  Handoff, and a WidgetKit extension use a
  privacy-preserving shared today snapshot. Focused tests cover the parser,
  persistence, readiness presentation, and platform snapshot contract. The parser
  now has 60+ phrase-level acceptance cases plus macOS `NaturalLanguage` tokenization
  parity coverage; the same framework is available to the iOS target.
- The app-side model extension was kept app-local; no upstream DB++ schema
  change is required for the current or planned product scope.
- **StoreKit cleanup:** the retired Pro subscription/trial/paywall path is
  removed from app launch, Settings, core models, and tests. `Cadence.storekit`
  contains only the optional `guru.parso.cladiron.tip.generous` consumable;
  successful purchase remains the sole path to the local Home Supporter badge.
- **Transparency and user control:** the project now requires visible status and
  plain-language control for automatic/background work. Settings exposes a
  Transparency & Control drill-down for HealthKit, Coach refresh, Watch
  projection, iCloud mirroring, Supporter prompts, and available retry/undo/
  recovery paths. Automatic HealthKit, coach, and iCloud progress no longer
  inserts transient rows into Home; explicit Watch-sync results remain visible
  as action feedback, and no reviewed workout is changed without explicit
  review and Apply.
- **iPad delivery smoke:** the iOS target now delivers to iPhone and iPad. The
  focused iPad smoke reuses the existing iPhone smoke method and checks only
  launch, absence of Plan, Settings, and Transparency & Control; it does not
  duplicate the iPhone workout flow or test retired bounded-planning UI.

### Remaining Phase 2 close-out

These are the two final real-device validations and should be run together:

1. Authored/automated-coach plan → iPhone persistence → Watch execution →
   phone reconciliation.
2. Same-user private iCloud convergence across supported devices.

Phase 2 is therefore implementation-green but not formally closed until those
hardware and private-sync checks pass. The previous release baseline is pushed;
the current history-index fix and documentation/smoke alignment must pass the
headless gate before release. No simulator is required for this pass.

### Remaining product work after this Phase 3 slice

- **Phase 4:** field-test readiness, widget, Shortcut, Handoff, larger-surface,
  accessibility, offline, and performance behavior; the bounded request parser
  is core-only after the weekly-planning UI retirement. Then complete the final
  acceptance matrix and Appendix AA compatibility proof.
- Across the remaining roadmap: add depth to cardio, mobility, instructions,
  larger-surface planning/templates/export, and the final v2.6 acceptance
  matrix plus Appendix AA compatibility proof.

Trainer mode, client sharing, Pro, trials, paywalls, and two-Apple-ID sharing
remain retired non-goals.

## Current work slice — Watch AppIcon recurrence guard — COMPLETE 2026-09-09

The Watch AppIcon files are present and valid, but a global `-sdk iphoneos`
override can force the embedded Watch target through the iPhone asset compiler.
This produces the misleading “AppIcon did not have any applicable content”
failure even when the Watch asset is correct. The checked-in Watch AppIcon
contract guard now validates the metadata, referenced PNG, dimensions, alpha
channel, and effective Watch target SDK. Repository-owned Xcode builds now run
through a wrapper that rejects explicit SDK overrides, and the destination-only
contract is checked in local guardrails and CI. Verification passed without
launching a simulator. The planner view-size violations were later cleared by
splitting the manual authoring and Planning surfaces into focused SwiftUI
files; the aggregate guardrails now pass.

## Current product scope correction — self-planned, automated coach only — COMPLETE 2026-09-09

The active roadmap is now explicitly single-user. There is no personal trainer,
client, Trainer mode, roster, human-coach delivery, invite/accept flow, CKShare
sharing, external-client packet, Pro tier, trial, paywall, or gated feature.
Planning is manual, template-based, or assisted by the automated scientific
coach; the user remains the author and accepts or edits suggestions.

The only planned purchase is an optional **$9.99 “Contribute to development”**
consumable. A successful purchase adds a **Supporter** badge to Home and
unlocks nothing. Core planning, coach assistance, execution, history, export,
partner sessions, and readiness remain available without purchase.

The authoritative plan and revision notes now mark the former trainer/client
and Pro roadmap as historical and retired. The active sequence is manual
self-planning, automated coach depth, optional Supporter handling, then
platform/readiness polish. Private iCloud remains limited to the user's own
devices. Existing compatibility code is not an invitation to expand the
retired model; remove or migrate it only as a separate cleanup task.

## Current investigation — cardio intensity credit consistency — INTERVAL-AWARE FIX COMPLETE 2026-09-15

Before this fix, the cardio paths disagreed. `TrainingEvent.from(cardio:userAge:)`
used both average and peak heart rate: at age 50, the app's age-based max HR is
about 173, so an average of 136 is 78.6% while a recorded peak of 170 is 98.3%;
the old peak threshold classified that session as vigorous and gave double
moderate-equivalent credit. The `YourWeekPresenter` intensity path used average
HR only, so it could show a lower/base intensity for the same workout. The HR
classification split was the defect addressed by the completed profile fix.

The better fix is not to promote the entire workout from its maximum sample. A
136 average with repeated 161 peaks at age 50 is consistent with an
interval-like effort: 136 is about 79% of the app's estimated HRmax of 173,
while 161 is about 93%. The current all-session buckets make that look like one
continuous moderate workout or, in the other path, incorrectly give the whole
session 2× credit. Official guidance also treats moderate and vigorous minutes
as additive and uses a 2:1 vigorous-to-moderate equivalence, so the app should
preserve the distribution of effort rather than discard it.

Implemented: `CardioZoneAggregator.IntensityProfile` now integrates the HR
curve over time with zone weights (easy 0.5×, moderate 1×, vigorous 2×). The
same profile feeds weekly zones, `TrainingEvent`, `CoachFacts`, and the Your
Week intensity surface. An `other` workout with at least two sustained Z4/Z5
bouts separated by recovery is marked interval-like without changing its
recorded modality. A single short peak does not trigger interval detection.
When samples are unavailable, the age/average/peak fallback remains in place
with lower confidence.

Regression coverage now includes age 50 / average 136 / repeated peak 161,
weighted high-zone credit, interval-like detection, isolated-peak rejection,
sampled `TrainingEvent` values, and conservative missing-HR fallback. The full
headless package suite now contains 1,802 tests; the current audit resolution
reran all 1,802 with zero failures. No simulator is required for this logic.

## Historical investigation — complete exercise variants and indexed search — core fix shipped 2026-09-10

The upstream coverage is present. Free Exercise DB++ v1.16.0 adds the
vendor-neutral `Machine_Hip_Thrust` record and carries **Glute Drive** as a
search alias, based on Hammer Strength and Matrix catalog review. The app pins
DB++ 1.16.0, but its bridge currently drops aliases before building
`ExerciseTemplate`, and the existing search index only sees canonical names and
facets. This is why `glute drive` fails even though the upstream data caught it.

The catalog/search model should separate **display variants** from **exercise
identity**:

- Preserve DB++ aliases through `ExerciseRecord` → `ExerciseTemplate`, keeping
  one stable canonical exercise identity for sets, history, volume, and coach
  logic.
- Materialize every canonical name and alias as a visible, grouped variant in
  the exercise view. Selecting “Glute Drive” or “Machine Hip Thrust” must resolve
  to the same canonical exercise rather than creating duplicate database rows.
- Build each search document from the canonical name, every full alias phrase,
  equipment, muscles, force, mechanics, and curated synonyms. Store/recompute
  the derived alias tokens in `Exercise.searchKeywords` so existing stores gain
  the same coverage.
- Replace the current per-query full-catalog scan with one reusable inverted
  index: normalized word/prefix → matching canonical IDs/variant labels. Intersect
  postings for multi-word AND queries, rank exact alias/phrase matches first, then
  prefixes, names, and facets. Build once per catalog snapshot and reuse on every
  iPhone/Watch keystroke; invalidate only when the catalog or custom-exercise set
  changes.

Add an idempotent catalog/search migration (bump the seed/index version and
recompute derived keywords for all built-ins, not only rows whose keywords are
empty). Add headless regression/performance tests proving that `glute drive`,
`machine glute drive`, canonical names, aliases, prefixes, and facet terms all
return the correct grouped variant immediately, while alias and canonical
selection share one exercise identity and one volume/history record.

## Session restart checkpoint — CloudKit schema protection

The entire SwiftData/CloudKit model graph was audited. Development and
Production now match the checked-in contract across all 20 app record types and
every field/type. The final automated guard discovered two fields that had been
missing from both environments:

- `CD_HRMDevice.CD_lastBattery` (`INT64`)
- `CD_SetEntry.CD_note` (`STRING`)

Both fields were added to Development and have now been deployed to Production.
The live verification command is:

```sh
bash scripts/check-cloudkit-schema.sh
```

It reports: `cloudkit-schema: Development and Production match the contract`.

The prevention work is committed in `94fe15d` (`test: add CloudKit schema
contract guard`):

- `CloudKitSchemaCoverageTests` asserts all 20 persisted models and their exact
  SwiftData attribute sets.
- `scripts/cloudkit-schema-contract.tsv` records every CloudKit record, field,
  and CloudKit type.
- `scripts/check-cloudkit-schema.sh` compares both live CloudKit environments
  against that contract when `~/.cloudkit-management-token` exists; without a
  token it still validates the checked-in contract for CI.
- `make guardrails` runs the schema guard, so the installed pre-commit hook and
  CI execute it. The hook is installed in this clone via
  `scripts/install-git-hooks.sh`.

Final audit passed: `CloudKitSchemaCoverageTests` 3/3, the credential-free
contract check, the authenticated Development/Production comparison, and all
`make guardrails` checks. The audit also found and repaired one generated
exercise-citation documentation drift. `git diff --check` passes and the
pre-commit hook is configured at `scripts/git-hooks`. The follow-up CloudKit
diagnostics, entitlement split, readiness-model registration, citation sync,
and checkpoint edits are included in the next focused commit.

### Phase 0 closure — 2026-09-08

Phase 0 is closed. The unified model, runtime materializer, normalized
persistence, Watch payload boundary, send preflight, private-iCloud
configuration, CloudKit schema contract, sharing contract, and sync-performance
hardening are implemented and covered by the automated gates.

Two hardware validations are intentionally moved out of Phase 0: the plan-origin
iPhone/Watch execution test and the same-user private-iCloud multi-device test
are both Phase 2 close-outs. They will be run together after manual planning and
automated-coach workflows are available. Human trainer/client sharing and
two-Apple-ID invite/accept testing are removed from the roadmap.

The complete SwiftData/CloudKit contract is deployed and verified in both
Development and Production; the schema tests, authenticated live comparison,
all guardrails, and the installed pre-commit hook are green. The schema
protection work and the follow-up CloudKit diagnostics, entitlement, readiness,
citation, and persistence/configuration changes are committed.

The simulator gates also pass after making the Watch exercise-picker smoke
fixture catalog-agnostic: it now selects the first available second chest
exercise and derives its delete identifier from that row. The plan-origin
iPhone/Watch smoke path and same-user private-iCloud device gate are now tracked
as Phase 2 close-outs rather than blocking this closure.
Phase 1 manual plan authoring now supplies the first half of that combined
validation; Phase 2 automated-coach workflows will supply the second half.

## Sole active plan — revised Cladiron MVP v2.5

Authoritative plan:
`docs/plans/cladiron-mvp-revised/CLADIRON_PLATFORM_SPEC.md`

Revision summary:
`docs/plans/cladiron-mvp-revised/REVISION-NOTES.md`

Visual contract:
`docs/plans/cladiron-mvp-revised/mockups/index.html`

All implementation work must advance this roadmap. Earlier field-test, exercise
database, and DB++ engine-adoption plans are historical inputs, not active plans.
Do not start a new standalone plan when the work belongs to a v2.6 phase or work
stream; update this file and the authoritative spec instead.

## Product and licensing boundary

Cladiron is public and free/open-source under GPLv3-or-later with the Cladiron
App Store Exception. The application source, UI, app-specific coaching
composition, persistence, and Apple-platform integrations are covered by that
license. The Cladiron name, icon, logo, screenshots, and other brand assets
remain protected under `TRADEMARKS.md`; `free-exercise-db-plusplus` and its
materials remain under their own license. Keep these boundaries consistent in
the repository, About, support screens, App Store metadata, and release
documentation. The optional contribution is not a paywall and must not gate
features.

## Shipped baseline — preserve, do not rebuild

The revised MVP starts from a mature iPhone/Watch app, not a greenfield project:

- SwiftData persistence mirrored through the user's private iCloud;
- iPhone and Watch strength, partner, cardio, and interval execution;
- HealthKit, BLE heart rate, WatchConnectivity, workout history, and export/import;
- cited observations, suggestions, progress, assessments, and StoreKit scaffolding;
- `free-exercise-db-plusplus` 1.16.0 pinned behind the sole
  `TrainingEngineBridge` import boundary;
- 873 built-in exercises, 20 normalized muscles, evidence-audited roles and
  volume credits, movement classifications, and package-backed evidence;
- deterministic DB++ self-planning, history-derived state, adaptation,
  progression, serialization, and training-engine contract tests;
- app-owned readiness, pain, recovery, eligibility, presentation, and citation
  policy composed around DB++.

Standing invariants: Swift 6 strict concurrency, deterministic explicit-date
engine calls, no runtime network path, additive-only persistence, warning-free
builds, stable exercise IDs, package evidence resolved to app citations, and no
second exercise database/decoder or DB++ import site.

## Historical checkpoint — Phase 1 manual planning — implementation complete 2026-09-10

The required spec audit is complete in the closure map linked below. It covers
§§7–10, §§39–42, §47.0, Phase 0, `WS-EXECUTION-COMPAT`, and Appendix AA.
The matrix marks every Phase 0 requirement as:

- **verified shipped** — cite implementation and tests;
- **partial** — identify the exact missing model, invariant, test, or UI seam;
- **not started** — define the smallest dependency-ordered implementation slice;
- **superseded by v2.5** — only where the spec explicitly adopts the DB++ or
  existing SwiftData implementation instead.

Regression coverage is frozen around today's editable workout/coach-plan
materializer, collapsed strength cards, full-screen set editor, performer history
and alternation, 20-muscle credits, Watch strength/cardio lifecycle, and durable
phone reconciliation. The first smallest adapter, versioned Watch-payload,
in-memory sharing-contract, additive persisted unified-plan envelope, CloudKit
shared-zone adapter, and unified `Session` → runtime materializer slices are
landed; they do not
replace working private-iCloud sync, unplanned workout paths, Watch execution,
cardio, partner behavior, history/export, or the DB++ bridge.

Audit and closure map: `docs/plans/cladiron-mvp-revised/PHASE-0-EXECUTION-COMPATIBILITY-AUDIT.md`.
The first adapter, versioned Watch-payload, in-memory sharing-contract,
additive persisted unified-plan envelope, CloudKit shared-zone adapter, and
unified `Session` → runtime materializer slices are now landed in `CadenceCore`
and covered by focused contract tests. The CloudKit adapter now preserves the
saved share URL, plan revision/sentAt, and deterministic last-writer-wins
behavior across device writers.
The payload preserves legacy Watch fields, carries rich strength prescriptions
and planned cardio, and is consumed by Watch launch and phone reconciliation.
The reconciliation fixtures cover duplicate/out-of-order results and source-ID
preservation; the private self-sync contract covers change tokens, append-only
results, and same-user multi-device plan convergence. The unified value-model
conversion preserves strength/cardio/mobility/instruction item identity, and the
repository has a single `Session`-based start entry point. The editable iPhone
start path now converts its draft through that entry point while retaining
partner and DB++ provenance metadata; the legacy `EditablePlan.apply` path
remains compatible. Coach-generated weekly plans now also bridge into the
unified seven-day value graph, persist through `UnifiedPlanStore`, and enrich
Watch payloads from the same sessions. Phase 1 now starts with real manual plan
authoring. The deferred plan-origin iPhone/Watch smoke path and private
self-sync validation are Phase 2 close-outs and should be run together after
automated-coach plan workflows are available.
Do not
implement later-phase UI before the Phase 0 model and sharing boundaries
needed by it are explicit.

## Current work slice — workout-entry surface cleanup — SHIPPED 2026-09-05

User-requested UI cleanup that does not alter the Phase 0 value model or
sharing boundaries: remove the Home-level “Suggest a Workout” CTA while keeping
the action inside the Start Workout flow, and remove the non-functional
“Generate with Coach” action from the Custom Workout editor. Preserve the
working suggested-workout chooser reached from Start Workout. Implemented in
the Home observations component and Custom Workout editor; the smoke contract
now asserts both removals and the retained entry point. Verification: `make ci`
(build, 1,718 tests, four guardrails) passed; `make smoke` passed on its second
run after an unrelated first-run simulator flake at This Week expansion.
The pre-commit full gate also passed iPhone smoke, Watch build/unit smoke, and
Watch execution smoke. GitHub Actions run `33982770430` could not start its
test job because the repository account's payments/spending limit is blocked;
no remote code failure was reported.

The plan-origin iPhone/Watch smoke path and same-user private-iCloud convergence
are now paired Phase 2 close-outs after real manual and automated-coach plan
authoring exist. The normalized persistence mapping is in place; human
trainer/client sharing is not planned.

## Current work slice — Phase 0 persistence and send safety — SHIPPED 2026-09-05

The next Phase 0 slice is implemented: unified plans now have normalized
SwiftData header/week/day/session/item/set rows with stable IDs, coach-generated
Home plans write the normalized tree alongside the compatibility envelope. The
legacy client-relationship/share metadata remains only as compatibility state;
the v2.6 roadmap does not expand it.
`PlanSendPreflight` now blocks shared plans that contain invalid or
unsnapshotted `%1RM` loads. The Apple-ID account gate is wired into app startup
and Settings, which reports the real iCloud account state rather than always
claiming sync is on. Focused tests cover all item families, stable-ID updates,
relationship round trips, preflight rejection, and account-status mapping.

The plan-origin iPhone/Watch smoke path and same-user private-iCloud convergence
are paired Phase 2 close-outs after real manual and automated-coach plan
authoring exists. The live two-Apple-ID invite/accept test and macOS Trainer
dependency are removed from the roadmap.

The unified cardio-to-Watch producer now preserves steady-state distance goals
and heart-rate zones (and interval work-zone metadata) through the versioned
`PlanSessionSnapshot`/`WatchPlanPayload` boundary. Focused adapter tests cover
the generated payload, including these fields; this closes a data-loss seam
before the remaining device smoke gate.

## Current work slice — private iCloud sync performance — SHIPPED 2026-09-10

The iPhone store was audited against the reported repeated-restore behavior. The
production path uses one SwiftData `ModelContainer` backed by Apple's managed
private CloudKit mirror; there is no app-owned full-workout-history `CKQuery`,
startup restore loop, or repeated manual download path. CloudKit may still import
and export while the app is running because Apple's managed mirror controls that
scheduling; there is no public SwiftData API that can force it to run immediately
or restrict it to launch only.

The app now coalesces short CloudKit import events before releasing Home into its
history-derived coach rebuild, preventing one rebuild per import event. Generated
coach plans and their normalized trees now use content-aware no-op upserts, so a
fresh generation timestamp alone does not rewrite SwiftData or enqueue another
CloudKit export. Settings now shows only account availability and a link to a
separate iCloud Details & Diagnostics view; storage, legacy recovery, and status
checks are off the main Settings screen. The diagnostics view explicitly labels
normal sync as automatic/incremental and does not pretend its Refresh Status
button can force Apple's managed sync.

Focused persistence tests and the full CI gate pass, including all guardrails
and the live Development/Production CloudKit schema comparison. The changes are
included in the Phase 2 implementation commit. The plan-origin iPhone/Watch
smoke path and same-user private-iCloud convergence are paired Phase 2
close-outs after real manual and automated-coach plan authoring exists; there is
no macOS Trainer dependency.

## Phase queue

### Phase 1 manual planning — implementation complete 2026-09-10

The Plan tab now has a real self-authored weekly-plan path: create a blank
Monday-first week, add up to two sessions per day, edit session titles, choose
an exercise from the bundled searchable catalog, edit set type/reps/load/%1RM,
rest, and target RPE, and save through both the compatibility envelope and the
normalized SwiftData plan tree. Authored plans retain stable plan/session/item/
set IDs and can launch through the existing unified runtime materializer, so
this slice is ready for the Phase 2 plan-origin execution close-out once
hardware validation is approved. Authored plans now also project today's supported
strength/cardio sessions into the versioned Watch payload while retaining the
legacy Watch fields. A pure execution-boundary classifier now keeps
strength-only on the existing iPhone runner, allows pure cardio to remain a
Watch target, and routes cardio, mobility, and cardio-plus-mobility sessions to
the dedicated combined runner; instruction-only and strength-plus-cardio mixes
remain explicitly unsupported. No non-strength session is mislabeled as
executable strength work.

The pure `ManualPlanBuilder` contract is covered by five focused tests for
blank-week shape, stable-ID session replacement, the two-sessions-per-day limit,
and all four item families through envelope/normalized persistence. The compact
authoring surface now edits strength, steady-state/interval/open cardio,
timed-or-repetition mobility, and instruction items while retaining their stable
IDs and preserving the existing strength-only start boundary. Mixed sessions are
saved and handed to the unified value/runtime boundary; they remain explicitly
blocked from the current strength-only runner until the later execution slice.
The pure `ManualPlanWatchBridge` contract is covered by four focused tests for
strength identity/prescriptions, cardio legacy-plus-rich payloads, and the
unsupported instruction-only and mixed-session boundaries. The new
`PlanExecutionBoundary` contract covers empty, strength-only, cardio-only,
mobility-only, instruction-only, and mixed sessions. The new headless
`CombinedExecutionPlan`/`CombinedPlanRunner` contract preserves item order,
auto-advances timed cardio, requires explicit completion for open cardio and
mobility, freezes while paused, and rejects strength/instruction items. The
authored-plan start path reserves a distinct combined live-workout lease and
opens the iPhone runner; completed cardio segments persist through the existing
cardio history path. The generic iOS device build and focused/full package tests
pass. The Watch AppIcon guard
and destination-based Xcode guard also pass; the unsafe global SDK invocation is
rejected before Xcode starts. The full aggregate guardrails now pass after the
planner view-size cleanup, and no simulator was run. Partner workouts
and partner history remain an explicit preservation boundary: unified plan
`PartnerRef`s, runtime active-partner IDs, performer-specific prescriptions,
`performedBy` set attribution, Watch partner rotation, and partner summary
history are all still owned by their existing persistence/sync paths. The new
Watch bridge only adds today's executable strength/cardio projection and does
not rewrite or discard those partner fields.

| Phase | Status | Next outcome |
|---|---|---|
| 0 — foundations and sync proof | **COMPLETE 2026-09-08** | closed; Phase 2 owns the deferred device close-outs |
| 1 — athlete app | **IMPLEMENTATION COMPLETE 2026-09-10** | Phase 2 close-out validation of plan-origin execution and private self-device sync |
| 2 — automated scientific coach | **IMPLEMENTATION GREEN; CLOSE-OUT PENDING** | run the authored/coach plan device path and same-user private-iCloud convergence together |
| 3 — self-planning depth + optional contribution | **IMPLEMENTATION COMPLETE 2026-09-10** | field-review plan depth, coach review, contribution badge, then continue to Phase 4 |
| 4 — individual-user platform polish | **IMPLEMENTATION COMPLETE 2026-09-11; FIELD REVIEW PENDING** | execute `PHASE_4_MANUAL_TEST.md`, then final acceptance and Appendix AA proof |

## Status and next task — 2026-09-17

Current status: Phase 0 is complete, Phase 1 implementation is complete, and
the Phase 2 implementation slice plus Phase 3 self-planning/contribution slice
are implemented. The history-index signature fix is awaiting the full headless
gate. Strength-only sessions
still use the existing iPhone/Watch runner; pure cardio remains projectable to
the existing Watch cardio runner and can also run through the authored-plan
combined surface; mobility and cardio-plus-mobility sessions use the new iPhone
runner, while instruction-only and strength-containing mixes remain blocked.
Partner workouts and partner history remain preserved.

Immediate next task: complete the headless gate for the history-index fix, then
complete the Phase 2 hardware/private-iCloud close-outs and the Phase 3/4 human
field checklists. Phase 4's current implementation includes readiness capture,
WidgetKit, App Shortcuts, Handoff, and the shared snapshot contract; bounded
planning remains core-only. Phase 2 hardware and private-iCloud close-outs
remain required field validation and are not replaced by simulator runs.

Overall plan position: Phase 3 and Phase 4 implementation are complete and
field-testable, Phase 2 is implementation-green and field-test ready but not
formally closed until the two real-device validations pass, and the remaining
work is field acceptance plus the final compatibility proof.

## Cardio suggestions — 2026-09-19

The first pushed audit slice is `64dc138` (`Harden navigation routes and audit
field plan`). The follow-up cardio-suggestion slice is implemented locally and
ready for its own commit: `Workout for You` now presents explicit Strength and
Cardio choices; cardio generation uses a value-only snapshot of persisted
cardio history plus the existing weekly moderate-equivalent dashboard; and the
pure `CardioSuggestionGenerator` produces bounded, conservative, cited
continuous sessions or gated intervals. Empty history falls back to an indoor
Run starter, while the most recent supported cardio type is reused when
history exists. The preview is explicit and routes continuous sessions through
the existing timer setup or established intervals through the existing HR gate
and interval runner. No DB++ or CloudKit schema change is required.

The cardio plan and audit are in `CARDIO_SUGGESTION_PLAN.md`. Core tests,
generic iOS build, `git diff --check`, and all non-simulator guardrails pass;
the new single iPhone smoke test also covers modality choice, cold-start cardio
generation, and preview cancellation. Remaining validation is the real-device
field test, not another simulator run.

## Execution rules

## Field-testing input — 2026-09-24

The next implementation slice addresses six field findings: add reliable
scroll-end clearance for This Week and Progress; replace Progress Strength over
Time's Powerlifter series with Bench Press, Squat, Deadlift, and their Combined
total; remove the unconditional Progress science banner in favor of contextual
The Science links; make Settings disclosure-based so its detail is opt-in; and
make Today → My Workouts completed-workout navigation resolve reliably instead
of landing on the generic warning surface. Preserve the existing root dock and
value-only navigation boundaries while adding focused coverage for the core
strength projection and route/clearance contracts.

Implementation is complete locally. This Week and Progress now add explicit
scroll-end clearance above the root dock; Progress exposes the four fixed
strength series and only contextual citation links; Settings uses collapsed
DisclosureGroups for optional detail; and completed workout destinations resolve
their SwiftData records in the destination view. Core tests (1847), the generic
iOS app build, `git diff --check`, and all non-simulator guardrails pass. The
updated iPhone smoke contract now taps a completed My Workouts row and verifies
that its summary opens and returns to Today. Per the repository workflow,
simulator execution was not completed because it requires an explicit user
request; the attempted smoke build was canceled promptly when that constraint
was clarified.

- Implement in phase and dependency order unless the spec explicitly identifies
  an independent work stream.
- Begin each work stream with a gap test against the shipped code; do not recreate
  an already-satisfied capability under a new type without a migration reason.
- Use the mockups as visual contracts, including dynamic type, accessibility,
  empty, loading, error, and offline states required by the
  spec even when a static mockup shows only the primary state.
- Keep the GPLv3/App Store Exception/open-project wording consistent in About/Help,
  support screens, App Store metadata, website copy, and release documentation.
  The optional contribution is not a paywall and must not gate features.
- Run focused tests during development and `make ci` before a phase/work-stream
  commit. The installed pre-commit hook runs only
  `swift test --package-path CadenceCore` and never boots a simulator. Run the
  iPhone/watch smoke gates explicitly before release, TestFlight submission, or
  field testing whenever their user flows change.
- Hardware verification remains mandatory for HealthKit, BLE, WatchConnectivity,
  workout runtime, and private-iCloud self-device sync on supported Apple
  surfaces. There is no human-coach sharing or Mail packet handoff gate.
- Do not push unless explicitly authorized. Preserve unrelated user changes.

## Definition of MVP-plan completion

The revised MVP is complete only when the active v2.6 acceptance criteria in §49
pass, the testing matrix in §50 is satisfied, the DB++ boundary remains intact,
the optional $9.99 contribution adds only the Home Supporter badge, and no core
feature is gated by purchase. Appendix AA must prove planning did not regress
DB++ muscle accounting, iPhone set entry, partners, cardio, or real-Watch
execution/reconciliation.
