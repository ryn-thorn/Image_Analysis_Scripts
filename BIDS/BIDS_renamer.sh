#!/bin/bash

# Usage:
#   ./rename_tree.sh /path/to/root "old_string" "new_string"

ROOT="$1"
OLD="$2"
NEW="$3"

if [[ -z "$ROOT" || -z "$OLD" || -z "$NEW" ]]; then
    echo "Usage: $0 ROOT_FOLDER OLD_STRING NEW_STRING"
    exit 1
fi

# Iterate deepest paths first
find "$ROOT" -depth -name "*$OLD*" | while IFS= read -r item; do
    newname="$(dirname "$item")/$(basename "$item" | sed "s/$OLD/$NEW/g")"
    mv "$item" "$newname"
done
