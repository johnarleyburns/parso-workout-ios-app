#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TARGET="$REPO_ROOT/CadenceCore/Sources/CadenceCore/Resources/free-exercise-db.json"
SOURCE_URL="https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"

echo "Fetching latest free-exercise-db from $SOURCE_URL ..."
TMP=$(mktemp)
if curl -fsSL --connect-timeout 10 --max-time 60 -o "$TMP" "$SOURCE_URL"; then
    if python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$TMP" 2>/dev/null; then
        cp "$TMP" "$TARGET"
        COUNT=$(python3 -c "import json; print(len(json.load(open('$TARGET'))))")
        echo "Updated: $COUNT exercises written to $TARGET"
    else
        echo "ERROR: Downloaded file is not valid JSON. Keeping existing snapshot."
        rm -f "$TMP"
        exit 1
    fi
else
    echo "WARNING: Download failed. Keeping existing snapshot at $TARGET"
    rm -f "$TMP"
    exit 0
fi
rm -f "$TMP"
