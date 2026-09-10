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

exec xcodebuild "$@"
