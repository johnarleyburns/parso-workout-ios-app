#!/usr/bin/env bash
set -euo pipefail

# Build the smaller offline Watch photo catalog from the full iPhone catalog.
# The Watch target must not link CadenceExerciseImages, because that would
# embed the 30 MB iPhone catalog through SwiftPM. These assets are copied into
# the Watch app's synchronized source tree instead.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${REPO_ROOT}/CadenceCore/Sources/CadenceExerciseImages/Resources/ExerciseImages"
DEST_DIR="${REPO_ROOT}/Cadence/Cadence Watch App Watch App/ExerciseImages"

MAX_DIMENSION=240
HEIC_QUALITY=55

command -v sips >/dev/null 2>&1 || { echo "error: sips not found (macOS only)"; exit 1; }
[ -d "${SOURCE_DIR}" ] || { echo "error: source catalog not found: ${SOURCE_DIR}"; exit 1; }

mkdir -p "${DEST_DIR}"
failed=0

while IFS= read -r -d '' source; do
    relative="${source#"${SOURCE_DIR}/"}"
    destination="${DEST_DIR}/${relative}"
    mkdir -p "$(dirname "${destination}")"
    if [ -f "${destination}" ]; then
        continue
    fi
    if ! sips -s format heic -s formatOptions "${HEIC_QUALITY}" \
        --resampleHeightWidthMax "${MAX_DIMENSION}" \
        "${source}" --out "${destination}" >/dev/null; then
        echo "  ! conversion failed: ${relative}" >&2
        rm -f "${destination}"
        failed=$((failed + 1))
    fi
done < <(find "${SOURCE_DIR}" -type f -name '*.heic' -print0)

echo "Watch catalog:"
du -sh "${DEST_DIR}"
echo "Files: $(find "${DEST_DIR}" -type f -name '*.heic' | wc -l | tr -d ' ')"
if [ "${failed}" -ne 0 ]; then
    echo "Conversions failed: ${failed}" >&2
    exit 1
fi
