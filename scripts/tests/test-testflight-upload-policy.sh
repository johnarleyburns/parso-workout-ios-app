#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/.github/scripts/testflight-upload.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp/bin/curl"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$tmp/bin/sleep"
chmod +x "$tmp/bin/sleep"

PATH="$tmp/bin:$PATH" RUNNER_TEMP="$tmp" bash "$script" -- bash -c 'exit 0'

counter="$tmp/transient-counter"
PATH="$tmp/bin:$PATH" RUNNER_TEMP="$tmp" bash "$script" -- bash -c '
  count=$(cat "$RUNNER_TEMP/transient-counter" 2>/dev/null || echo 0)
  count=$((count + 1)); echo "$count" > "$RUNNER_TEMP/transient-counter"
  if [[ "$count" -eq 1 ]]; then echo "Defaults.properties timed out"; exit 1; fi
' >"$tmp/transient-output" 2>&1
[[ $(cat "$counter") -eq 2 ]]
[[ $(grep -c 'TestFlight upload attempt' "$tmp/transient-output") -eq 2 ]]

set +e
PATH="$tmp/bin:$PATH" RUNNER_TEMP="$tmp" bash "$script" -- bash -c 'echo "package validation failed"; exit 7' >"$tmp/output" 2>&1
status=$?
set -e
[[ "$status" -eq 7 ]]
[[ $(grep -c 'TestFlight upload attempt' "$tmp/output") -eq 1 ]]

echo "TestFlight upload retry policy: passed"
