#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

chmod +x scripts/git-hooks/pre-commit scripts/git-hooks/pre-push
git config core.hooksPath scripts/git-hooks

echo "Installed git hooks from scripts/git-hooks"
echo "pre-commit: swift test --package-path CadenceCore (no simulator)"
echo "pre-push: make pre-push"
