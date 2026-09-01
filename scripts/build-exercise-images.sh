#!/usr/bin/env bash
#
# build-exercise-images.sh — one-shot pipeline that bundles exercise imagery so
# the app never fetches a photo at runtime (NFR-3, revenue plan Phase 3, D3).
#
# Run this ONCE on a Mac, then COMMIT the output under
#   CadenceCore/Sources/CadenceCore/Resources/ExerciseImages/<id>/{0,1}.heic
# It is NOT run at build time and NOT run in CI.
#
# Source: free-exercise-db, pinned to commit b0eed06 — the same upstream data
# free-exercise-db++ carries verbatim under each record's `source` field, so the
# JSON and the imagery can never drift.
#
# Downscale + re-encode with `sips` (ships with macOS — no new dependency, per
# the repo's zero-proprietary-deps rule NFR-6).
#
# Idempotent: an already-converted <id>/N.heic is skipped, so re-running only
# fetches what is missing. Delete the output dir to force a full rebuild.

set -euo pipefail

COMMIT="b0eed06"
BASE_URL="https://raw.githubusercontent.com/yuhonas/free-exercise-db/${COMMIT}/exercises"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DB_JSON="${REPO_ROOT}/CadenceCore/.build/checkouts/free-exercise-db-plusplus/free-exercise-db-plusplus.json"
if [[ ! -f "$DB_JSON" ]]; then
  DB_JSON="${REPO_ROOT}/.build/dd/SourcePackages/checkouts/free-exercise-db-plusplus/free-exercise-db-plusplus.json"
fi
OUT_DIR="${REPO_ROOT}/CadenceCore/Sources/CadenceCore/Resources/ExerciseImages"

command -v sips >/dev/null 2>&1 || { echo "error: sips not found (macOS only)"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "error: curl not found"; exit 1; }
[ -f "${DB_JSON}" ] || { echo "error: ${DB_JSON} not found"; exit 1; }

mkdir -p "${OUT_DIR}"

# Every "<id>/<n>.jpg" image path referenced by the pinned JSON.
IMAGE_PATHS="$(python3 -c "
import json
d = json.load(open('${DB_JSON}'))
for e in d['exercises'].values():
    for img in e['source'].get('images', []):
        print(img)
")"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

total=0
fetched=0
skipped=0
failed=0

while IFS= read -r rel; do
    [ -n "${rel}" ] || continue
    total=$((total + 1))
    id="$(dirname "${rel}")"
    n="$(basename "${rel}" .jpg)"
    dest_dir="${OUT_DIR}/${id}"
    dest="${dest_dir}/${n}.heic"

    if [ -f "${dest}" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    mkdir -p "${dest_dir}"
    src="${TMP}/src.jpg"
    if ! curl -fsSL "${BASE_URL}/${rel}" -o "${src}"; then
        echo "  ! fetch failed: ${rel}"
        failed=$((failed + 1))
        continue
    fi

    if sips -s format heic -s formatOptions 70 \
            --resampleHeightWidthMax 400 "${src}" --out "${dest}" >/dev/null 2>&1; then
        fetched=$((fetched + 1))
    else
        echo "  ! convert failed: ${rel}"
        rm -f "${dest}"
        failed=$((failed + 1))
    fi
    rm -f "${src}"

    if [ $((total % 100)) -eq 0 ]; then
        echo "  … ${total} processed (${fetched} new, ${skipped} skipped, ${failed} failed)"
    fi
done <<< "${IMAGE_PATHS}"

echo
echo "Done. total=${total} new=${fetched} skipped=${skipped} failed=${failed}"
echo "Pinned commit: ${COMMIT}"
echo -n "Bundle size: "
du -sh "${OUT_DIR}"

if [ "${failed}" -ne 0 ]; then
    echo "WARNING: ${failed} images failed — re-run to retry (the pipeline is idempotent)."
    exit 1
fi
