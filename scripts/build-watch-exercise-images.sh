#!/usr/bin/env bash
set -euo pipefail

# Build the smaller offline Watch photo catalog from the full iPhone catalog.
# ImageMagick owns the resize and metadata stripping. The local ImageMagick
# package currently ships a HEIC module whose dynamic-loader metadata is broken,
# so sips is used only to decode/encode Apple's HEIC container at the edges.
# The Watch target must not link CadenceExerciseImages, because that would
# embed the 30 MB iPhone catalog through SwiftPM. These assets are copied into
# the Watch app's synchronized source tree instead. Xcode flattens that
# synchronized resource group into the app bundle, so each filename includes
# its exercise ID to avoid 0.heic/1.heic collisions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${REPO_ROOT}/CadenceCore/Sources/CadenceExerciseImages/Resources/ExerciseImages"
DEST_DIR="${REPO_ROOT}/Cadence/Cadence Watch App Watch App/ExerciseImages"

MAX_DIMENSION=240
HEIC_QUALITY=55

command -v magick >/dev/null 2>&1 || { echo "error: ImageMagick (magick) not found"; exit 1; }
command -v sips >/dev/null 2>&1 || { echo "error: sips not found (macOS only)"; exit 1; }
[ -d "${SOURCE_DIR}" ] || { echo "error: source catalog not found: ${SOURCE_DIR}"; exit 1; }

mkdir -p "${DEST_DIR}"
convert_one() {
    local source="$1"
    relative="${source#"${SOURCE_DIR}/"}"
    exercise="$(dirname "${relative}")"
    position="$(basename "${relative}" .heic)"
    destination="${DEST_DIR}/${exercise}_${position}.heic"
    local temp_dir
    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/cadence-watch-image.XXXXXX")"
    local source_png="${temp_dir}/source.png"
    local resized_png="${temp_dir}/resized.png"
    local output_heic="${temp_dir}/output.heic"

    # Decode the source with Apple's codec, resize with ImageMagick, then use
    # Apple's codec again for the HEIC container written into the Watch bundle.
    if ! sips -s format png "${source}" --out "${source_png}" >/dev/null \
        || ! magick "${source_png}" -auto-orient \
            -resize "${MAX_DIMENSION}x${MAX_DIMENSION}>" -strip \
            "${resized_png}" \
        || ! sips -s format heic -s formatOptions "${HEIC_QUALITY}" \
            "${resized_png}" --out "${output_heic}" >/dev/null; then
        echo "  ! conversion failed: ${relative}" >&2
        rm -rf "${temp_dir}"
        return 1
    fi
    mv -f "${output_heic}" "${destination}"
    rm -rf "${temp_dir}"
}

export SOURCE_DIR DEST_DIR MAX_DIMENSION HEIC_QUALITY
export -f convert_one
set +e
find "${SOURCE_DIR}" -type f -name '*.heic' -print0 \
    | xargs -0 -n 1 -P "${WATCH_IMAGE_JOBS:-8}" bash -c 'convert_one "$1"' _
status=$?
set -e

echo "Watch catalog:"
du -sh "${DEST_DIR}"
echo "Files: $(find "${DEST_DIR}" -type f -name '*.heic' | wc -l | tr -d ' ')"
if [ "${status}" -ne 0 ]; then
    echo "One or more conversions failed" >&2
    exit 1
fi
