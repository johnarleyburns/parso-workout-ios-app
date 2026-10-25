#!/usr/bin/env bash
# Guards the WatchConnectivity trap (issue #359): reply/error handlers run on a
# background queue, so closures formed inside a main-actor AppModel method
# inherit its isolation and trap. They must come from nonisolated static factories.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/Cadence/Cadence/App/AppModel.swift"
body="$(awk '/private func sendWatchStateQuery/{f=1} f{print} f&&/^    }$/{exit}' "$FILE")"
[ -n "$body" ] || { echo "watch-handler-isolation: sendWatchStateQuery not found" >&2; exit 1; }
if grep -nE 'replyHandler: *\{|errorHandler: *\{' <<<"$body"; then
  echo "watch-handler-isolation: inline WatchConnectivity handler in sendWatchStateQuery" >&2
  exit 1
fi
grep -q 'replyHandler: Self.watchStateReplyHandler' <<<"$body" &&
grep -q 'errorHandler: Self.watchStateErrorHandler' <<<"$body" ||
  { echo "watch-handler-isolation: handlers must come from nonisolated factories" >&2; exit 1; }
grep -q 'nonisolated private static func watchStateReplyHandler' "$FILE"
grep -q 'nonisolated private static func watchStateErrorHandler' "$FILE"
echo "watch-handler-isolation: ok"
