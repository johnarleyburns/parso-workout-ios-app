#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' 'build completed' > "$tmp/clean.log"
printf '%s\n' 'warning: Apple generated metadata skipped' >> "$tmp/clean.log"
bash "$(dirname "$0")/check-owned-warnings.sh" "$tmp/clean.log"
printf '%s\n' '/checkout/CadenceCore/Sources/Foo.swift:1: warning: owned diagnostic' > "$tmp/owned.log"
if bash "$(dirname "$0")/check-owned-warnings.sh" "$tmp/owned.log"; then
  echo 'warning classifier fixture failed to reject owned warning' >&2
  exit 1
fi
echo 'warning classifier fixtures: OK'
