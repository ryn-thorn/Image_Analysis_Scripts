#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Usage
# ============================================================
# ./copy_subject_files.sh <input_dir> <output_dir>
#
# Example:
#   ./copy_subject_files.sh /data/input /data/output
# ============================================================

# --- Parse inputs ---
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <input_dir> <output_dir>"
    exit 1
fi

input_dir=$1
output_dir=$2

# --- Check input directory ---
if [[ ! -d "$input_dir" ]]; then
    echo "Error: input_dir '$input_dir' not found!"
    exit 1
fi

# --- Create output directory if it doesn't exist ---
mkdir -p "$output_dir"

# --- Loop over subject subfolders ---
for subj_dir in "$input_dir"/*; do
    [[ -d "$subj_dir" ]] || continue  # skip if not a folder
    subj=$(basename "$subj_dir")
    echo "Processing subject: $subj"

    # Make a subject-specific folder in output
    subj_out="$output_dir/$subj"
    mkdir -p "$subj_out"

    # Files to copy
    for filetype in SUV T1 CTAC; do
        # Look for either .nii or .nii.gz
        file=$(find "$subj_dir" -maxdepth 1 -type f \( -name "${filetype}.nii" -o -name "${filetype}.nii.gz" \) | head -n 1)
        if [[ -n "$file" ]]; then
            echo "  Found $filetype → copying..."
            cp "$file" "$subj_out/"
        else
            echo "  Warning: $filetype not found for $subj"
        fi
    done
done

echo "✅ Done! Files copied to: $output_dir"
