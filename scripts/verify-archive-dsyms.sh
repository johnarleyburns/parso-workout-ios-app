#!/usr/bin/env bash
# Fails unless every app-owned Mach-O in the archive has a dSYM with the same UUID.
# Output is UUID-only: never filesystem paths or signing data.
# Usage: scripts/verify-archive-dsyms.sh <archive.xcarchive>
set -euo pipefail
archive="${1:?archive path required}"
app="$archive/Products/Applications/Cadence.app"
dsyms="$archive/dSYMs"
[[ -d "$app" && -d "$dsyms" ]] || { echo "Archive app or dSYMs directory is missing" >&2; exit 1; }

uuids() { # prints one UUID per architecture of each Mach-O given
  local f
  for f in "$@"; do
    dwarfdump --uuid "$f" 2>/dev/null | sed -n 's/^UUID: \([0-9A-Fa-f-]*\) .*/\1/p'
  done
}

binaries=()
while IFS= read -r bundle; do
  exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Info.plist" 2>/dev/null || true)
  [[ -n "$exe" && -f "$bundle/$exe" ]] && binaries+=("$bundle/$exe")
done < <(find "$app" \( -name '*.app' -o -name '*.appex' \) -type d | sort)
[[ ${#binaries[@]} -gt 0 ]] || { echo "No app-owned binaries found" >&2; exit 1; }

dsym_files=()
while IFS= read -r f; do dsym_files+=("$f"); done < <(find "$dsyms" -path '*Contents/Resources/DWARF/*' -type f)
have=$(uuids "${dsym_files[@]}" | tr 'a-f' 'A-F' | sort -u)

missing=0
while IFS= read -r uuid; do
  [[ -z "$uuid" ]] && continue
  if grep -qx "$(printf '%s' "$uuid" | tr 'a-f' 'A-F')" <<<"$have"; then
    echo "dSYM present for UUID $uuid"
  else
    echo "dSYM MISSING for UUID $uuid" >&2
    missing=1
  fi
done < <(uuids "${binaries[@]}")
exit "$missing"
