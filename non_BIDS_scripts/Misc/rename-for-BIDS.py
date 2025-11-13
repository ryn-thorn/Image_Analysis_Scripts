#!/usr/bin/env bash
set -euo pipefail

##########################################################
# Recursive Rename Script
# Replace a user-supplied string with "sub-" in all names
# Usage: ./rename_string_to_sub.sh <base_directory> <string_to_replace>
##########################################################

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <base_directory> <string_to_replace>"
    exit 1
fi

BASE_DIR="$1"
SEARCH_STR="$2"
REPLACEMENT="sub-"
LOG_FILE="${BASE_DIR%/}/rename_log.csv"

echo "old_path,new_path,status" > "$LOG_FILE"

# Walk deepest paths first to avoid rename conflicts
find "$BASE_DIR" -depth | while IFS= read -r path; do
    dirname=$(dirname "$path")
    basename=$(basename "$path")

    # Skip if it doesn't contain the search string
    if [[ "$basename" != *"$SEARCH_STR"* ]]; then
        continue
    fi

    new_basename="${basename//${SEARCH_STR}/${REPLACEMENT}}"
    new_path="${dirname}/${new_basename}"

    if [[ "$path" != "$new_path" ]]; then
        if [[ -e "$new_path" ]]; then
            echo "\"$path\",\"$new_path\",FAILED (exists)" >> "$LOG_FILE"
            echo "⚠️  Skipping rename: target already exists -> $new_path"
        else
            mv "$path" "$new_path"
            if [[ -e "$new_path" ]]; then
                echo "\"$path\",\"$new_path\",OK" >> "$LOG_FILE"
            else
                echo "\"$path\",\"$new_path\",FAILED" >> "$LOG_FILE"
            fi
        fi
    fi
done

echo "✅ Rename complete. Log saved to: $LOG_FILE"
