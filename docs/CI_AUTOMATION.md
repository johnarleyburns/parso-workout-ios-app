# CI/CD automation (issue → PR → merge → TestFlight)

Code is the source of truth; this is the operator's map.

Generated PRs open ready for review and immediately request auto-merge. Required checks and branch protection still determine merge eligibility. A refused auto-merge request leaves the PR open for reconciliation; it never falls back to an immediate merge.

## Ownership
| Responsibility | Owner |
|---|---|
| Intake, authorization, idempotency, implementation | `issue-to-pr.yml` + `issue-to-pr.sh` (macOS, Claude, no token in Claude's env) |
| Validation | `pr-validation.yml` → `scripts/ci-validate.sh` (read-only token, no secrets). Same script used by issue and repair agents |
| Diagnosis + repair (one PR per run) | `pr-conflict-repair.yml` + `pr-conflict-repair.sh` |
| Readiness, branch freshness, auto-merge, backlog, escalation | `pr-maintenance.yml` + `pr-maintenance.sh` (Linux, trusted `main` checkout, no Claude, no PR code) |
| Post-merge build/TestFlight + reporting | `ios.yml` (release secrets only here) |

## State machine (`decide()` in pr-maintenance.sh)
stopped → nothing · dirty/failed → repair (≤3 persisted attempts) else exhausted+escalate · action_required → escalate (never "passed") · cancelled → re-run · missing → close/reopen to re-emit `pull_request` (≤2) · pending → wait · success+behind → `update-branch` (GitHub-side normal merge, no force) · success+unknown → wait · success otherwise → ready + auto-merge · already armed → waiting-merge.
Freshness uses REST `mergeable_state` / `compare behind_by` (drafts report `draft`, so compare is used); GraphQL `MERGEABLE` is never used. Validation status comes from the `pr-validation.yml` `pull_request` run **for the PR head SHA**.
Separate facts: local validation ≠ GitHub `validate` check ≠ merged ≠ TestFlight upload ≠ Apple processing (never claimed).

## Triggers
Maintenance: completion of Validation/Repair/Issue workflows, push to `main`, every 20 min, manual (`pr_number` also clears a stop and resets the budget). Every run sweeps all open Claude PRs, so coalesced/superseded runs lose nothing. Repair: dispatched per PR, concurrency group per PR (different PRs never cancel each other; a duplicate pending request for the same PR is re-dispatched by the next sweep). Issue: group per issue.

## Authorization
Only `johnarleyburns`-authored issues. `.github` edits need `ai-ci-maintenance` applied *by the owner* (checked on the label event actor) and only to the 8 listed paths. If Claude needs `.github` without it, the run exits **successfully as "waiting"**: label `awaiting-ci-authorization` + one comment. Applying `ai-ci-maintenance` triggers the workflow and resumes. Existing PR for the issue → resume/reconcile, never a second PR; closed issue, merged or rejected PR → not restarted.

## Retry budget and failures
3 Claude attempts per failure generation, stored in a single per-PR status comment (`<!-- claude-pr-state {...} -->`), reset when validation passes. Transient infra failures (rate limit, 5xx, runner loss) re-run the job (≤2) without consuming a Claude attempt. Exhaustion: repair run exits **1**, label `needs-human-review`, one issue comment mentioning the owner (category, head, attempts, excerpt, run link). The stop applies to that head only; a new push, or manual maintenance dispatch with `pr_number`, resumes.

## Security model
- Validation: `contents: read`, no secrets, no write token (`persist-credentials: false`).
- Maintenance: never checks out/executes PR code; scripts run from an immutable copy of `main`.
- Claude and validation run with `GH_TOKEN` unset; the token is injected per `git` command only for fetch/push. Pushes are normal (never force). Staged paths (adds, deletes, renames, untracked, symlinks) are checked against the `.github` allow-list and a signing/credential denylist before commit. Forks and non-`claude/issue-N-RUN` branches are ignored. Issue text, PR text and CI logs are passed as fenced *untrusted* data.
- Release/App Store secrets appear only in `ios.yml` on `main`.
- Residual risk: Claude runs with `bypassPermissions` on a runner that also holds `CLAUDE_CODE_OAUTH_TOKEN`; mitigated by owner-only issues, no push token in its env, and the path gate. Full isolation would need ephemeral runners.

## Required settings (owner)
1. `CLAUDE_WORKFLOW_TOKEN`: fine-grained PAT or App token (contents, pull requests, issues, actions: write) of a user with write access, so pushes/`update-branch` start workflows and are not `action_required`. Bot-`GITHUB_TOKEN` pushes never start workflows.
2. Repo → Settings → Actions → General: *Allow GitHub Actions to create and approve PRs* is not needed; keep fork-approval policy strict. `action_required` for a same-repo PAT push means the token user lacks write access or the approval policy is stricter than expected — the reconciler escalates it.
3. Enable *Allow auto-merge*; keep the `validate` required check and up-to-date policy.
4. Labels are created on demand.

## Observability
Each maintenance run writes `pr-maintenance-report.json` (artifact + step summary): open Claude PRs, validating, repairing, behind, conflicted, waiting for merge, stopped. Post-merge outcome is commented on the merged PR by `ios.yml`'s `deployment-report`.

## macOS capacity and simulator policy
macOS jobs use GitHub-hosted runner capacity without a shared job-level concurrency group. Workflow-level locks still serialize releases and writers for each PR or issue, and validation cancels superseded runs for the same PR. During scheduling recovery, keep maintenance, conflict repair, and issue generation disabled and dispatch validations in small batches only after confirming runner assignment and completion. Do not bulk rebase branches or dispatch replacement runs to clear a queue.

CI only performs host SwiftPM tests and generic physical-device-target builds/archives. `scripts/check-ci-no-simulators.sh` rejects simulator-bearing CI commands statically, and `xcodebuild-safe.sh` rejects simulator destinations and `xcodebuild test` at runtime when `GITHUB_ACTIONS=true`. Local smoke targets remain local-only.

## Emergency pause
Disable the *Claude PR Maintenance* and *Claude PR Conflict Repair* workflows in the Actions tab (or remove the secret `CLAUDE_WORKFLOW_TOKEN`: maintenance then fails loudly).

## Backlog bootstrap
After this merges, dispatch *Claude PR Maintenance* once (no input). It diagnoses every open Claude PR individually (#97 behind → update-branch; drafts with passing checks → ready + auto-merge; dirty/failed → repair; `action_required` → escalate; stale `needs-human-review` labels clear when the head moves). The 20-minute schedule continues thereafter.

## Testing
`scripts/tests/test-pr-maintenance.sh` (run by `scripts/ci-validate.sh`) covers the decision table, REST-vs-GraphQL state, validation-run mapping, and a mocked-`gh` sweep. **Not yet done:** the live end-to-end canaries (tests A–H of issue #123) — they require the merged workflows and real runners and must be executed after merge.
