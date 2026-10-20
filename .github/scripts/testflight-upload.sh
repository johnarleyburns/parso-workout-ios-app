#!/usr/bin/env bash
# Runs one App Store Connect upload command with evidence for, and a bounded
# retry of, the known transient Apple Transporter bootstrap failure.  Do not
# retry validation, signing, or package errors: those need a real repair.
set -euo pipefail

if [[ "${1:-}" != "--" || $# -lt 2 ]]; then
  echo "usage: $0 -- upload-command [args...]" >&2
  exit 64
fi
shift

transport_url='https://contentdelivery.itunes.apple.com/transporter/Defaults.properties'
log_file="${RUNNER_TEMP:-/tmp}/testflight-transport.log"
attempts=3

is_transient_transport_failure() {
  grep -Eiq 'Defaults\.properties|transporter.*(timed out|connection|network)|NSURLErrorDomain.*-(1001|1005|1009)|network connection was lost|could not resolve host|SSL.*(timeout|connection)' "$log_file"
}

for attempt in $(seq 1 "$attempts"); do
  : > "$log_file"
  echo "TestFlight transport preflight $attempt/$attempts: $transport_url"
  if ! curl --fail --silent --show-error --location \
      --connect-timeout 15 --max-time 45 --retry 2 --retry-delay 2 --retry-all-errors \
      "$transport_url" -o "${RUNNER_TEMP:-/tmp}/transporter-defaults.properties" 2>&1 | tee -a "$log_file"; then
    if [[ "$attempt" -eq "$attempts" ]]; then
      echo "Apple Transporter bootstrap endpoint remained unreachable after $attempts attempts." >&2
      exit 1
    fi
    sleep $((attempt * 15))
    continue
  fi

  echo "TestFlight upload attempt $attempt/$attempts"
  set +e
  "$@" 2>&1 | tee -a "$log_file"
  upload_status=${PIPESTATUS[0]}
  set -e
  if [[ "$upload_status" -eq 0 ]]; then
    exit 0
  fi
  if ! is_transient_transport_failure || [[ "$attempt" -eq "$attempts" ]]; then
    echo "Upload failed with a non-retryable error, or retries are exhausted." >&2
    exit "$upload_status"
  fi
  echo "Transient Apple Transporter failure detected; retrying without rebuilding."
  sleep $((attempt * 15))
done
