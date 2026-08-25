#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'cp "$tmp/CITATIONS.md" "$repo_root/docs/CITATIONS.md"; rm -rf "$tmp"' EXIT
cp "$repo_root/docs/CITATIONS.md" "$tmp/CITATIONS.md"
python3 "$repo_root/scripts/generate-exercise-citations.py"
diff -u "$tmp/CITATIONS.md" "$repo_root/docs/CITATIONS.md"
echo "citation sync guardrail: OK"
