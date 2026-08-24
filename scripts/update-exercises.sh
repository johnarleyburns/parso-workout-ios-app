#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TARGET="$REPO_ROOT/CadenceCore/Sources/CadenceCore/Resources/free-exercise-db-plusplus.json"
SOURCE_URL="https://raw.githubusercontent.com/johnarleyburns/free-exercise-db-plusplus/main/free-exercise-db-plusplus.json"

echo "Fetching latest free-exercise-db++ from $SOURCE_URL ..."
TMP=$(mktemp)
if curl -fsSL --connect-timeout 10 --max-time 120 -o "$TMP" "$SOURCE_URL"; then
    if python3 "$SCRIPT_DIR/validate-exercise-db.py" "$TMP"; then
        cp "$TMP" "$TARGET"
        echo "Updated: $TARGET"
    else
        echo "ERROR: Downloaded file failed schema validation. Keeping existing snapshot."
        rm -f "$TMP"
        exit 1
    fi
else
    echo "WARNING: Download failed. Keeping existing snapshot at $TARGET"
    rm -f "$TMP"
    exit 0
fi
rm -f "$TMP"
