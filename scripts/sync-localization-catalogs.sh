#!/usr/bin/env bash
# Extracts every localizable string with the Swift compiler (SWIFT_EMIT_LOC_STRINGS)
# and syncs the String Catalogs, exactly as Xcode does when it builds.
#
# Run this after adding or changing UI text. New keys arrive with no
# translations; add them in every catalog locale with state `needs_review`, and
# let a native speaker flip them to `translated` in Xcode's catalog editor.
# Never copy the English text into another language as a placeholder.
#
# Package code (CadenceCore, CadenceFeatures) looks strings up with
# `bundle: .module`, so each package target has its own catalog.
#
# One generic iOS build covers the iPhone app, the embedded Watch app and both
# widget extensions. Like every xcodebuild here it must not overlap another
# build or test job.
set -euo pipefail
cd "$(dirname "$0")/.."

derived_data="${CADENCE_L10N_DERIVED_DATA:-/tmp/cadence-l10n}"
bash scripts/xcodebuild-safe.sh -project Cadence/Cadence.xcodeproj -scheme Cadence \
  -destination 'generic/platform=iOS' -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO -quiet build

stringsdata() {
  find "$derived_data/Build/Intermediates.noindex" -path "*/Debug-*/$1.build/*" -name '*.stringsdata'
}

sync() {
  local target="$1"; shift
  local files=()
  while IFS= read -r file; do files+=("$file"); done < <(stringsdata "$target")
  [ "${#files[@]}" -gt 0 ] || { echo "no .stringsdata for $target" >&2; exit 1; }
  xcrun xcstringstool sync "$@" --stringsdata "${files[@]}"
}

sync Cadence Cadence/Cadence/Localizable.xcstrings Cadence/Cadence/AppShortcuts.xcstrings
sync "Cadence Watch App Watch App" "Cadence/Cadence Watch App Watch App/Localizable.xcstrings"
sync CadenceWidgets CadenceWidgets/Localizable.xcstrings
sync CadenceWatchWidgets CadenceWatchWidgets/Localizable.xcstrings
sync CadenceCore CadenceCore/Sources/CadenceCore/Resources/Localizable.xcstrings
sync CadenceFeatures CadenceCore/Sources/CadenceFeatures/Resources/Localizable.xcstrings

echo "Catalogs synced. Stale keys are marked extractionState=stale; remove them once confirmed unused."
