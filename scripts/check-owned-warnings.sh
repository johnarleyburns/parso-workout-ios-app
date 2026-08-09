#!/usr/bin/env bash
set -euo pipefail

# Swift 6 migration warning gate. Build logs are passed as arguments; paths are
# normalized so the gate behaves the same locally and on CI.
if (($# == 0)); then
  echo "usage: $0 BUILD_LOG [BUILD_LOG ...]" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
owned='(CadenceCore|Cadence|scripts|Package\.swift|project\.pbxproj|asset catalog)'
failed=0
for log in "$@"; do
  [[ -f "$log" ]] || { echo "warning gate: missing log: $log" >&2; failed=1; continue; }
  normalized="$(sed "s#${root}#<checkout>#g; s#/Users/[^/]*/github/[^/]*/#<checkout>/#g" "$log")"
  while IFS= read -r line; do
    [[ "$line" == *warning:* ]] || continue
    if [[ "$line" =~ $owned ]]; then
      echo "warning gate: owned warning: $line" >&2
      failed=1
    fi
  done <<< "$normalized"
done
((failed == 0)) || { echo "warning gate: FAILED" >&2; exit 1; }
echo "warning gate: OK"
