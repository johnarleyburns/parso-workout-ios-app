#!/usr/bin/env bash
# No-network guardrail (revenue plan Phase 3, decision D3, NFR-3).
#
# Cladiron's headline claim is a no-network core: it works in airplane mode and
# never phones home. This turns that from an aspiration into an enforced property
# by failing CI if any runtime image/data fetching API reappears in the app or
# core sources.
#
# IMPORTANT: this bans the FETCHING APIs, not URLs. Citation.swift legitimately
# holds ~53 paper URLs, and ExerciseDetailView shows a free-exercise-db attribution
# link — those are DISPLAYED and opened in Safari on tap, never fetched by the app.
# So we never grep for the string "http".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

# Directories whose runtime code must never fetch.
SEARCH_DIRS=(
  "$ROOT/CadenceCore/Sources"
  "$ROOT/Cadence/Cadence"
)

# Fetching APIs. Word-boundaried where it matters so we don't match unrelated
# identifiers. `.data(from:` is URLSession's async fetch; `Data(contentsOf:` with
# a remote URL would also fetch, but it is used legitimately for Bundle.module
# file URLs — so we ban the unambiguous network entry points only.
BANNED_PATTERNS=(
  'URLSession'
  'URLRequest'
  'dataTask'
  'AsyncImage'
  '\.data\(from:'
  '\.upload\('
  '\.download\('
)

for dir in "${SEARCH_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  for pat in "${BANNED_PATTERNS[@]}"; do
    # --include limits to Swift; exclude test files, which may legitimately mock.
    matches="$(grep -rEn --include='*.swift' "$pat" "$dir" 2>/dev/null || true)"
    if [ -n "$matches" ]; then
      echo "❌ no-network guardrail: banned fetching API '$pat' found:"
      echo "$matches"
      fail=1
    fi
  done
done

if [ "$fail" -ne 0 ]; then
  echo
  echo "no-network guardrail: FAILED"
  echo "The app must not fetch at runtime (NFR-3). Bundle the resource instead, or"
  echo "if a legitimate exception truly arises, document it and update this script."
  exit 1
fi
echo "no-network guardrail: OK"
