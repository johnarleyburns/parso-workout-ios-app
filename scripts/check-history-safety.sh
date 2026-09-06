#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ENTRY="$ROOT/Cadence/Cadence/CadenceApp.swift"
STORE_SOURCE="$ROOT/CadenceCore/Sources/CadenceCore/Store.swift"

# This is intentionally independent of SwiftData behavior tests. It prevents a
# future startup change from bringing back the exact destructive reset that
# erased pre-schema-3 local history. Any intentional storage cleanup must be
# reviewed separately and must not be added to either startup file.
if command -v rg >/dev/null 2>&1; then
  search_destructive() {
    rg -n 'destroyDefaultStore|schemaVersionKey|removeItem|FileManager\.default\.remove' "$APP_ENTRY" "$STORE_SOURCE"
  }
  search_guard() {
    rg -n 'without altering stored workout history' "$APP_ENTRY"
  }
else
  search_destructive() {
    grep -nE 'destroyDefaultStore|schemaVersionKey|removeItem|FileManager\.default\.remove' "$APP_ENTRY" "$STORE_SOURCE"
  }
  search_guard() {
    grep -nE 'without altering stored workout history' "$APP_ENTRY"
  }
fi

if search_destructive; then
  echo "history-safety: destructive store reset code found in app startup/store" >&2
  exit 1
fi

if ! search_guard >/dev/null; then
  echo "history-safety: startup failure path is missing its non-destructive guard" >&2
  exit 1
fi

echo "history-safety: destructive startup reset guard OK"
