#!/usr/bin/env bash
# The coding agent in every automation path is OpenCode on DeepSeek Flash,
# invoked non-interactively with auto-approved permissions. No Claude Code
# binary, OAuth token, or turn budget may remain.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
for script in issue-to-pr.sh pr-conflict-repair.sh release-repair.sh; do
  file="$root/.github/scripts/$script"
  grep -Fq 'OPENCODE_MODEL' "$file"
  grep -Fq 'opencode --standalone run' "$file"
  grep -Fq -- '--auto' "$file"
  ! grep -Fq 'claude -p' "$file"
  ! grep -Fq 'CLAUDE_CODE_OAUTH_TOKEN' "$file"
  ! grep -Fq 'ANTHROPIC_MODEL' "$file"
done
for workflow in issue-to-pr.yml pr-conflict-repair.yml release-repair.yml; do
  file="$root/.github/workflows/$workflow"
  grep -Fq 'https://opencode.ai/v2/install' "$file"
  grep -Fq 'OPENCODE_MODEL' "$file"
  grep -Eq 'timeout-minutes: (120|360)' "$file"
  ! grep -Fq 'claude.ai/install.sh' "$file"
  ! grep -Fq 'CLAUDE_CODE_OAUTH_TOKEN' "$file"
done
echo "OpenCode agent invocation: passed"
