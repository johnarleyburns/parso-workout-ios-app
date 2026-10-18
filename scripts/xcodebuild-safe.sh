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

  # CI must never start an iOS or watchOS simulator. Local smoke commands keep
  # working, but a CI invocation fails before xcodebuild is allowed to launch.
  # macOS still ships Bash 3.2.  `${value,,}` needs Bash 4+, so normalize with
  # POSIX character classes instead of making the CI safety wrapper itself fail.
  argument_lower=$(printf '%s' "$argument" | tr '[:upper:]' '[:lower:]')
  if [[ "${GITHUB_ACTIONS:-}" == "true" && "$argument_lower" == *simulator* ]]; then
    echo "xcodebuild-safe: simulator destinations are forbidden in CI" >&2
    exit 2
  fi

  if [[ "${GITHUB_ACTIONS:-}" == "true" && ( "$argument" == "test" || "$argument" == "test-without-building" ) ]]; then
    echo "xcodebuild-safe: xcodebuild simulator tests are forbidden in CI; use host SwiftPM tests and generic device builds" >&2
    exit 2
  fi
done

exec xcodebuild "$@"
