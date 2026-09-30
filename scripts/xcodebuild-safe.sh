#!/usr/bin/env bash
set -euo pipefail

# This wrapper is intentionally repository-local. It protects the mixed iOS /
# embedded-watchOS project from the exact invocation that caused the recurring
# AppIcon failure: a global -sdk override applied to a scheme with both targets.
for ((index = 1; index <= $#; index++)); do
  argument="${!index}"
  case "$argument" in
    -sdk|-sdk=*|SDKROOT=*)
      echo "xcodebuild-safe: refusing an explicit SDK override for the mixed iOS/watchOS project" >&2
      echo "xcodebuild-safe: use -destination 'generic/platform=iOS' or 'generic/platform=watchOS'" >&2
      exit 2
      ;;
  esac
done

# Xcode resolves Swift packages into DerivedData independently of SwiftPM's
# CadenceCore checkout. Resolve and patch that checkout before every project
# build so a clean machine does not compile DB++ 1.17.0's incompatible
# HealthInterop.swift source for the Watch target.
project=""
scheme=""
derived_data_path=""
arguments=("$@")
for ((index = 0; index < ${#arguments[@]}; index++)); do
  case "${arguments[index]}" in
    -project)
      if (( index + 1 < ${#arguments[@]} )); then project="${arguments[index + 1]}"; fi
      ;;
    -scheme)
      if (( index + 1 < ${#arguments[@]} )); then scheme="${arguments[index + 1]}"; fi
      ;;
    -derivedDataPath)
      if (( index + 1 < ${#arguments[@]} )); then derived_data_path="${arguments[index + 1]}"; fi
      ;;
  esac
done
if [[ -n "$project" && -n "$scheme" ]]; then
  resolve_arguments=(-resolvePackageDependencies -project "$project" -scheme "$scheme")
  if [[ -n "$derived_data_path" ]]; then
    resolve_arguments+=(-derivedDataPath "$derived_data_path")
  fi
  xcodebuild "${resolve_arguments[@]}"
fi
patch_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patch-dbpp-healthinterop.sh"
if [[ -n "$derived_data_path" ]]; then
  bash "$patch_script" "$derived_data_path"
else
  bash "$patch_script"
fi

exec xcodebuild "$@"
