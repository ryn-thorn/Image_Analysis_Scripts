#!/usr/local/bin/bash
set -euo pipefail

#############################################
# Native Space Subcortical ROI Analysis (BIDS-Compatible)
# Version: 1.6
# Author: Ryn Thorn
#############################################

# ============================================
# Usage
# ============================================
if [[ $# -lt 5 || $# -gt 6 ]]; then
    echo "Usage: $0 <FS_BASE> <OUT_BASE> <DKI_BASE> <RAW_BASE> <THRESH_SCRIPT> [NUM_JOBS]"
    exit 1
fi

FS_BASE=$1
OUT_BASE=$2
DKI_BASE=$3
RAW_BASE=$4
THRESH_SCRIPT=$5
NUM_JOBS=${6:-4}  # default 4 parallel jobs

# Log file for missing files
MISSING_LOG="${OUT_BASE}/missing_inputs.log"
> "$MISSING_LOG"

echo "============================================"
echo "BIDS-Compatible Native Space ROI Analysis"
echo "============================================"
echo "FreeSurfer base: $FS_BASE"
echo "Output base:     $OUT_BASE"
echo "DKI base:        $DKI_BASE"
echo "RAW base:        $RAW_BASE"
echo "Threshold script: $THRESH_SCRIPT"
echo "Parallel jobs:   $NUM_JOBS"
echo "Missing inputs log: $MISSING_LOG"
echo

# ============================================
# Detect all subject/session pairs
# ============================================
echo "🔍 Scanning for FreeSurfer subjects..."
mapfile -t SUBJECT_PATHS < <(find "$FS_BASE" -type f -path "*/ses-*/mri/aparc+aseg.mgz" -print 2>/dev/null | sort)

if [[ ${#SUBJECT_PATHS[@]} -eq 0 ]]; then
    echo "❌ No aparc+aseg.mgz files found under $FS_BASE"
    exit 1
fi

echo "✅ Found ${#SUBJECT_PATHS[@]} FreeSurfer session(s)."
echo

# ============================================
# Helper: Run a single subject/session
# ============================================
run_subject_session() {
    aseg_path="$1"

    # --- Derive identifiers ---
    mri_dir=$(dirname "$aseg_path")
    ses=$(basename "$(dirname "$mri_dir")")      # e.g., ses-pretreatment
    subj_dir=$(dirname "$(dirname "$mri_dir")")  # .../sub-214
    subj=$(basename "$subj_dir")

    echo "=== Processing $subj / $ses ==="

    fs_t1_mgz="${mri_dir}/T1.mgz"
    subj_out="${OUT_BASE}/${subj}/${ses}"
    mkdir -p "$subj_out"

    dki_dir="${DKI_BASE}/${subj}/${ses}"
    raw_dir="${RAW_BASE}/${subj}/${ses}"

    # --- Check required files ---
    missing=false
    if [[ ! -f "$fs_t1_mgz" ]]; then
        echo "$subj/$ses: Missing T1.mgz" | tee -a "$MISSING_LOG"
        missing=true
    fi
    if [[ ! -d "$dki_dir" ]]; then
        echo "$subj/$ses: Missing DKI directory" | tee -a "$MISSING_LOG"
        missing=true
    fi

    if [[ "$missing" == true ]]; then
        echo "Skipping $subj/$ses due to missing files."
        return
    fi

    # --- Convert T1 ---
    echo "🧠 Converting T1.mgz → NIfTI..."
    fs_t1_nii="${subj_out}/FS_T1.nii.gz"
    if [[ ! -f "$fs_t1_nii" ]]; then
        mri_convert "$fs_t1_mgz" "$fs_t1_nii" >/dev/null
    fi

    # --- Convert aseg ---
    echo "🧩 Converting aparc+aseg.mgz..."
    fs_aseg="${subj_out}/aparc+aseg.nii.gz"
    if [[ ! -f "$fs_aseg" ]]; then
        mri_convert "$aseg_path" "$fs_aseg" >/dev/null
    fi

    # --- Threshold aseg to make ROIs ---
    echo "🎯 Thresholding ROIs..."
    THRESH=0.4  # example threshold value
    ASEG_THRESH="${subj_out}/aparc+aseg_thr.nii.gz"
    if [[ ! -f "$ASEG_THRESH" ]]; then
        python "$THRESH_SCRIPT" "$fs_aseg" "$ASEG_THRESH" "$THRESH" || \
            echo "$subj/$ses: Thresholding failed" | tee -a "$MISSING_LOG"
    else
        echo "Skipping threshold_nifti.py — already exists: $ASEG_THRESH"
    fi

    # --- Copy DKI metrics and check existence ---
    metrics_dir="$dki_dir/metrics"
    if [[ ! -d "$metrics_dir" ]]; then
        echo "$subj/$ses: Missing metrics directory" | tee -a "$MISSING_LOG"
    else
        cp "$metrics_dir"/*.nii "$subj_out" 2>/dev/null || true
        for metric in dti_fa dti_md dki_mk; do
            if [[ ! -f "$metrics_dir/${metric}.nii" ]]; then
                echo "$subj/$ses: Missing metric ${metric}.nii" | tee -a "$MISSING_LOG"
            fi
        done
    fi

    echo "✅ Completed $subj/$ses"
}

export -f run_subject_session
export OUT_BASE DKI_BASE RAW_BASE THRESH_SCRIPT MISSING_LOG

# ============================================
# Run in parallel
# ============================================
printf "%s\n" "${SUBJECT_PATHS[@]}" | parallel --env OUT_BASE --env DKI_BASE --env RAW_BASE --env THRESH_SCRIPT --env MISSING_LOG -j "$NUM_JOBS" run_subject_session {}

echo
echo "🎉 All sessions processed successfully!"
echo "⚠️  Check $MISSING_LOG for any missing files."
