# Field-testing PR audit

Scope: every item in requirements.md, PRs #753–#771 (including ledger #758).
This is a source, test-coverage and integration audit. It does not claim rendered
device validation or a passing full Apple build. NO SIMULATORS were launched or
run. Required CI remains the full SwiftData/SwiftUI build and unit-test gate.

## Findings and fixes by requirement

| Item | PR | Audit finding and disposition |
| --- | --- | --- |
| a | #756 | Two-column non-weighted label matches the request. Found Crown still using weight-step increments when weight focus was retained, despite editing reps; fixed shared step policy, rep focus highlight, and 1–100 rep range. Added a Crown regression. |
| b | #760 | No new source discrepancy: dots/state/builder removed; set card and exercise list share the same 32-point progress ring, count and progress semantics; name reserves two lines. Existing presentation/card regressions cover progress. |
| c | #764 | Shared prospective/persisted calculations no longer double bell loads. Strengthened coverage across all six single/paired/isolateral dumbbell/kettlebell modes, including an isometric-named movement and legacy multiplier=2. Barbell and added-bodyweight behavior remain unchanged. |
| d | #765 | Found that comparing submitted reps with a recomputed default could mistake attribution changes for explicit rep edits. Added an explicit edit flag to the real editor draft model and carried it through SetDraft. Rep entry/stepper regressions added. Existing override isolation, Watch flow, schema and native archive regressions retained. |
| e | #768 | Found More depended on changing a selection, new Watch suggestions omitted info links, sent-workout rows exceeded the requested idle home layout, and WatchLiftLaunch's synthesized initializer was internal. Fixed explicit recent-choice/full-catalog navigation; added info links; moved sent drafts to My Workouts; exposed a public initializer and added a non-@testable API regression. Restored the 400-line view budget after the changes. |
| f | #767 | Found Quick Start used an empty plan-materialization path rather than the existing empty-session launcher; fixed it. More is now an explicit menu action, including when already selected/no recents. Suggested now checks the same-day cache at tap time instead of trusting a preview across midnight; added a cache boundary regression. Removed obsolete scheduling/recommendation hero code while retaining safe Resume/adoption. |
| g | #763 | Absolute thresholds and both ring legends matched. Found remaining Strength footer totals/Cardio link and Cardio headings using default/pink/teal colors. Bound them to the shared weekly color policy. Boundary regressions cover zero and both thresholds for both modalities. |
| h | #754 | No new source discrepancy: selected subtab anchors on appearance and selection changes; existing persistence/default tests establish Strength over time as the fresh default. Actual scrolling needs device verification. |
| i1 | #762 | No standalone source gap: Suggest Workout removed from both shipped weekly tab surfaces. Its merge overlap with color changes was resolved on #771, preserving both removal and shared tint. |
| i2 | #757 | No new source discrepancy: count removed from the shipped weekly Strength heading and old strength-start view. #771 keeps the old view deleted rather than resurrecting it when integrating this PR. |
| j | #759 | No new source discrepancy: actual weekly muscle sets render as m/12 using the existing fractional formatter; values are not clamped to 12. VoiceOver reads muscle plus weekly count. |
| k | #761 | No new source discrepancy: titles changed on the actual HomeView strength/cardio tab owners, not only a similarly named legacy picker. |
| l | #755 | Merged with passing CI. No source discrepancy: Find's exercise picker requests an always-visible navigation search drawer. First-frame rendered visibility is still a device check. |
| m | #766 | Phone compact/expanded/single-suggestion detail controls remain visible; details resolve from the local store when opened. Watch legacy suggestion review/single-exercise flows expose details. The additional new Watch-home flow was fixed on #768 so it does not bypass this requirement. Missing library data shows an explanation rather than silently hiding the control. |
| n | #770 | Found unused scheduling-date helpers, a future-date error and canStartOrSchedule naming left after UI/API removal; removed/renamed them. Restored corrupt-draft START coverage that had been deleted with the scheduling assertion. Creation/reschedule APIs, date-picker UI, scheduling promotion and Watch injection are gone. Legacy entities/codecs remain for store/export compatibility and start/delete of saved drafts. |
| o | #769 | No further source discrepancy after auditing recording, transcription, interpretation, gestures, microphone controls, intents, sync handlers, settings, permissions and tests. Remaining retired key strings are only reset cleanup/legacy-input regression data. Spoken OUTPUT cues remain. #771 resolves its overlap with sticky logging without restoring voice adjustments. |
| p | #753 | No new source discrepancy: Daily step target control and associated explanatory footer/citation removed from Settings. Existing encoded preferences remain readable. |
| q | #771 | Found an alternate-sheet Quick Start still using empty plan materialization and a smoke flow assuming exercise selection opened the editor. Fixed the alternate route and explicit Add Set step. Retired view declarations/callers and obsolete picker policies/tests are removed; the real Cardio weekly tab stays. Combined branches now preserve all fixes across color/suggestion, delete/modify and sticky-reps/voice overlaps. |
| ledger | #758 | Updated the requirements ledger and added this per-PR audit. Acceptance boxes stay unchecked until the applicable CI/device checks pass. |

## CI orchestration discrepancy

The issue-pause variable also disabled scheduled PR maintenance. Green PRs behind
main could therefore remain waiting despite auto-merge being enabled. New PR
#772 separates the PR-maintenance pause control from issue admission, with
hermetic regressions and updated automation documentation. Issue admission stays
paused with CLAUDE_PIPELINE_AUTO_ENABLED=false. This change is submitted through
PRs, not written directly to main; until it merges, the old pause behavior remains.

## Verification performed

- Parsed every added/modified Swift file in the combined #771 branch with the
  Swift frontend: pass. Parsing does not establish Apple type-check/build success.
- git diff against main --check: pass.
- scripts/check-ci-no-simulators.sh: pass.
- scripts/check-test-pyramid.sh: pass (one iPhone and one Watch UI flow; neither executed).
- scripts/ci-validate.sh --fast: pass, including shell/YAML checks, 30 crash-intake
  tests / 133 assertions and the hermetic automation regressions.
- Four portable Swift policy tests passed in an isolated Linux package using
  actual production policy source and existing test bodies: strength color
  boundaries, cardio color boundaries, strength/recent-cardio choices and the
  non-weighted Crown step. This is not a replacement for the full app suite.
- Full Apple builds and SwiftData unit regressions remain queued/running in
  required CI. Real-device visual/navigation/workout checks were not executed.

## Integration and remaining verification

Original feature PRs retain the individual changes and auto-merge settings.
#771 now contains their combined source heads plus #772 so required CI can
validate the final interaction rather than only isolated patches. Merge conflicts
were resolved by preserving the requested final behavior, not by choosing one
feature over another. No direct push to main, admin merge or check bypass occurred.

No known source-level requirement discrepancy remains after these fixes.
This does not mark the release device-verified. In particular, Watch text fit,
native picker/search/scroll behavior, offline suggestion generation and workout
handoff still require the real-device checklists in the PRs after CI produces a
TestFlight build. Historical bell calculations intentionally use stored totals
without doubling; legacy scheduling storage remains read-compatible.
