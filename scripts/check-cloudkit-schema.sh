#!/usr/bin/env bash
set -euo pipefail

# CloudKit schema guardrail.
#
# The SwiftData schema is the source of truth for the app, while this contract
# records the exact CloudKit names/types that must exist after schema deployment.
# The local unit test catches model drift; this script catches remote Development
# and Production drift when a CloudKit management token is available.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACT="$ROOT/scripts/cloudkit-schema-contract.tsv"
CONTAINER_ID="iCloud.guru.parso.ios-workout-app"
TEAM_ID="3264Y8YUGV"
TOKEN_FILE="${CLOUDKIT_MANAGEMENT_TOKEN_FILE:-${HOME}/.cloudkit-management-token}"

fail=0

if [[ ! -f "$CONTRACT" ]]; then
  echo "cloudkit-schema: contract is missing: $CONTRACT" >&2
  exit 1
fi

# Validate the checked-in contract itself before trusting it for live checks.
duplicate_lines="$({ awk -F '\t' '$1 !~ /^#/ && NF == 3 {print}' "$CONTRACT" | sort | uniq -d; } || true)"
if [[ -n "$duplicate_lines" ]]; then
  echo "cloudkit-schema: duplicate contract entries:" >&2
  echo "$duplicate_lines" >&2
  fail=1
fi

invalid_lines="$({ awk -F '\t' '$1 !~ /^#/ && NF != 3 {print NR ": " $0}' "$CONTRACT"; } || true)"
if [[ -n "$invalid_lines" ]]; then
  echo "cloudkit-schema: malformed contract lines:" >&2
  echo "$invalid_lines" >&2
  fail=1
fi

invalid_types="$({ awk -F '\t' '$1 !~ /^#/ && NF == 3 && $3 !~ /^(STRING|INT64|DOUBLE|TIMESTAMP|BYTES)$/ {print NR ": " $0}' "$CONTRACT"; } || true)"
if [[ -n "$invalid_types" ]]; then
  echo "cloudkit-schema: unsupported CloudKit types in contract:" >&2
  echo "$invalid_types" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

normalize_schema() {
  local schema_file=$1
  awk '
    /^    RECORD TYPE CD_/ {
      record = $3
      in_record = 1
      next
    }
    in_record && index($0, "    );") == 1 {
      in_record = 0
      next
    }
    in_record && $1 ~ /^CD_/ {
      print record "\t" $1 "\t" $2
    }
  ' "$schema_file" | sort
}

contract_entries() {
  awk -F '\t' '$1 !~ /^#/ && NF == 3 {print $1 "\t" $2 "\t" $3}' "$CONTRACT" | sort
}

contract_records() {
  contract_entries | cut -f1 | sort -u
}

schema_records() {
  rg '^    RECORD TYPE CD_' "$1" | awk '{print $3}' | sort -u
}

compare_schema() {
  local label=$1 schema_file=$2
  local normalized="$schema_file.normalized"
  normalize_schema "$schema_file" > "$normalized"

  if ! diff -u <(contract_entries) "$normalized"; then
    echo "cloudkit-schema: $label does not match the checked-in contract" >&2
    fail=1
  fi
  if ! diff -u <(contract_records) <(schema_records "$schema_file"); then
    echo "cloudkit-schema: $label record types do not match the checked-in contract" >&2
    fail=1
  fi
}

if [[ ! -r "$TOKEN_FILE" ]]; then
  echo "cloudkit-schema: local contract OK; live check skipped (no management token at $TOKEN_FILE)"
  exit 0
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "cloudkit-schema: local contract OK; live check skipped (xcrun unavailable)"
  exit 0
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/cladiron-cloudkit-schema.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

for environment in development production; do
  schema_file="$tmp_dir/$environment.dsl"
  echo "cloudkit-schema: exporting $environment schema"
  CLOUDKIT_MANAGEMENT_TOKEN="$(< "$TOKEN_FILE")" \
    xcrun cktool export-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment "$environment" \
      --output-file "$schema_file"
  compare_schema "$environment" "$schema_file"
done

if [[ "$fail" -ne 0 ]]; then
  echo "cloudkit-schema: FAILED — deploy the Development schema to Production or update the contract with reviewed additive changes" >&2
  exit 1
fi

echo "cloudkit-schema: Development and Production match the contract"
