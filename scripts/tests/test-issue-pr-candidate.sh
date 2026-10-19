#!/usr/bin/env bash
# Regression-test the production candidate gate's crucial Git exit semantics.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/.github/scripts/issue-to-pr.sh"
grep -Fq "if git diff --cached --quiet; then" "$script"
grep -Fq "return 10" "$script"
grep -Fq "git diff --cached --check" "$script"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
git -C "$tmp" config user.email test@example.invalid
git -C "$tmp" config user.name test
printf 'base\n' > "$tmp/file"
git -C "$tmp" add file && git -C "$tmp" commit -qm base
# Empty index: git diff --quiet succeeds. A candidate gate must classify empty.
git -C "$tmp" diff --cached --quiet
# Modified, added and deleted paths each make --quiet return 1, which is the
# successful nonempty-candidate condition the harness must preserve.
printf 'changed\n' > "$tmp/file"; git -C "$tmp" add file
if git -C "$tmp" diff --cached --quiet; then echo 'modified staged diff misclassified as empty' >&2; exit 1; fi
git -C "$tmp" reset --hard -q
printf 'new\n' > "$tmp/new"; git -C "$tmp" add new
if git -C "$tmp" diff --cached --quiet; then echo 'added staged diff misclassified as empty' >&2; exit 1; fi
git -C "$tmp" reset --hard -q; rm -f "$tmp/new"
git -C "$tmp" rm -q file
if git -C "$tmp" diff --cached --quiet; then echo 'deleted staged diff misclassified as empty' >&2; exit 1; fi
echo 'issue-to-pr candidate gate: nonempty diffs are publishable candidates'
