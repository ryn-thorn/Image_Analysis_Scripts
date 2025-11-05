#!/bin/bash
# usage: ./flatten_fs_dirs.sh /path/to/freesurfer/base

set -euo pipefail

base_dir="$1"

echo "Scanning for nested subject folders inside: $base_dir"
echo

# Loop through each subject directory
for subj_dir in "$base_dir"/*/; do
    [ -d "$subj_dir" ] || continue

    subj_name=$(basename "$subj_dir")
    inner_dir="${subj_dir}${subj_name}"

    # Check if nested folder exists
    if [ -d "$inner_dir" ]; then
        echo "⚙️  Found nested folder for $subj_name"
        echo "    Moving contents from:"
        echo "      $inner_dir"
        echo "    → $subj_dir"
        echo

        # Move everything inside inner_dir up one level
        shopt -s dotglob nullglob
        mv "$inner_dir"/* "$subj_dir"/

        # Remove now-empty nested folder
        rmdir "$inner_dir"

        echo "✅  Fixed: $subj_name"
        echo
    fi
done

echo "All done!"
