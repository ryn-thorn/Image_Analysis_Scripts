#!/usr/bin/env bash
##############################################
# Freesurfer recon-all wrapper
# Runs recon-all for multiple subjects
##############################################
#
# ./freesurfer-reconall.sh --input /path/to/T1s --output /path/to/freesurfer_output --subjects A001 A002 A003

set -euo pipefail

usage() {
    echo "Usage: $0 --input /path/to/data --output /path/to/freesurfer --subjects subj1 subj2 ..."
    exit 1
}

error_exit() {
    echo -e "\033[1;31mERROR:\033[0m $1" >&2
    exit 1
}

# --- Args ---
INPUT=""
OUTPUT=""
SUBJECTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input) INPUT="$2"; shift 2;;
        --output) OUTPUT="$2"; shift 2;;
        --subjects) shift; while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do SUBJECTS+=("$1"); shift; done;;
        -h|--help) usage;;
        *) echo "Unknown argument: $1"; usage;;
    esac
done

[[ -z "$INPUT" || -z "$OUTPUT" || ${#SUBJECTS[@]} -eq 0 ]] && usage

# --- Logging ---
mkdir -p "$OUTPUT"
LOGFILE="$OUTPUT/freesurfer-reconall.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "===================================="
echo "Run started: $(date)"
echo "Input dir: $INPUT"
echo "Output dir (SUBJECTS_DIR): $OUTPUT"
echo "Subjects: ${SUBJECTS[*]}"
echo "===================================="

export SUBJECTS_DIR="$OUTPUT"

# --- Run recon-all ---
for subj in "${SUBJECTS[@]}"; do
    subj_dir="$INPUT/$subj"

    if [[ ! -d "$subj_dir" ]]; then
        echo "Skipping $subj: folder not found in $INPUT"
        continue
    fi

    # Find T1 file
    t1_file=$(find "$subj_dir" -maxdepth 1 -type f -iname "*T1*.nii" | head -n 1)
    if [[ -z "$t1_file" ]]; then
        echo "Skipping $subj: no T1 file found in $subj_dir"
        continue
    fi

    echo "Running recon-all for $subj ..."
    recon-all -all -i "$t1_file" -subjid "$subj" || {
        echo "Recon-all failed for $subj"
        continue
    }
done

echo "===================================="
echo "All done: $(date)"
echo "===================================="
