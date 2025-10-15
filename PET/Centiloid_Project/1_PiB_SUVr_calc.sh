#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PET PiB mSUVr Calculation for Centiloid Calibration
# ============================================================
# Usage:
#   ./PiB_SUVr_calc.sh <suv_dir> <voi_dir>
#
# Example:
#   ./pet_to_t1_registration_single.sh \
#       /data/PET_SUV-to-T1_registration \
#       /path/to/Centiloid_Std_VOI/nifti/1mm 
# ============================================================

BASE_DIR=$1
VOI_DIR=$2

mkdir -p "$BASE_DIR"
OUT_CSV="$BASE_DIR/mSUVr_all_subjects.csv"

# Initialize CSV if not already created
if [[ ! -f "$OUT_CSV" ]]; then
    echo "subject,mSUVr" > "$OUT_CSV"
fi

# Find VOI files
# VOI_CTX=$(find "$VOI_DIR" -type f -name "*voi_ctx_1mm.nii*" | head -n1 || true)
# VOI_WB=$(find "$VOI_DIR" -type f -name "*voi_WhlCblBrnStm_1mm.nii*" | head -n1 || true)
# MNI=$(find "$VOI_DIR" -type f -name "*MNI152_T1_1mm.nii*" | head -n1 || true)
VOI_CTX="$VOI_DIR/voi_ctx_1mm.nii"
VOI_WB="$VOI_DIR/voi_WhlCblBrnStm_1mm.nii"
MNI="$VOI_DIR/MNI152_T1_1mm.nii.gz"

if [[ -z "$VOI_CTX" || -z "$VOI_WB" ]]; then
    echo "❌ Could not find VOI files in $VOI_DIR"
    exit 1
fi

# ============================================================
# Helper: find a .nii or .nii.gz file reliably
# ============================================================
find_file() {
    local subj_dir="$1"
    local pattern="$2"
    find "$subj_dir" -maxdepth 1 -type f -name "$pattern" | head -n1
}

# ============================================================
# Process a single subject
# ============================================================
process_subject() {
    local SUBJ_DIR="$1"
    local VOI_CTX="$2"
    local VOI_WB="$3"
    local BASE_DIR="$4"

    local SUBJ
    SUBJ=$(basename "$SUBJ_DIR")
    local SUBJ_OUT="$BASE_DIR/$SUBJ"
    mkdir -p "$SUBJ_OUT"

    echo "----------------------------------------------------"
    echo "🧠 Processing subject: $SUBJ"
    echo "----------------------------------------------------"

    # Find input files
    SUV_T1="$SUBJ_DIR/SUV_REG_reslice.nii.gz"
    T1="$SUBJ_DIR/T1.nii.gz"

    # Define output filenames
    MNI_T1="$SUBJ_OUT/MNI_in_T1.nii.gz"
    MNI_T1_WARP="$SUBJ_OUT/MNI_in_T1.mat"
    VOI_CTX_WARP="$SUBJ_OUT/voi_ctx_in_T1.nii.gz"
    VOI_WB_WARP="$SUBJ_OUT/voi_WB_in_T1.nii.gz"
    
    # -----------------------------
    # 4. Warp Centiloid VOIs (skip if done)
    # -----------------------------
    if [[ -f "$VOI_CTX_WARP" && -f "$VOI_WB_WARP" ]]; then
        echo "✅ [$SUBJ] VOIs already warped — skipping"
    else
        echo "➡️  [$SUBJ] Warping VOIs to T1 space"
        
        flirt -in "$MNI" \
              -ref "$T1" \
              -out "$MNI_T1" \
              -omat "$MNI_T1_WARP" 
              
         flirt -in "$VOI_CTX" \
               -ref "$T1" \
               -applyxfm -init "$MNI_T1_WARP" \
               -out "$VOI_CTX_WARP"    

         flirt -in "$VOI_WB" \
               -ref "$T1" \
               -applyxfm -init "$MNI_T1_WARP" \
               -out "$VOI_WB_WARP"                                   
    fi

    # -----------------------------
    # 5. Compute mSUVr (always recompute to keep CSV fresh)
    # -----------------------------
    if grep -q "$SUBJ" "$OUT_CSV"; then
        echo "⚠️  [$SUBJ] Entry already exists in CSV — skipping mSUVr calc"
        return
    fi

    SUVR_CTX=$(fslmeants -i "$SUV_T1" -m "$VOI_CTX_WARP" || echo "")
    SUVR_WB=$(fslmeants -i "$SUV_T1" -m "$VOI_WB_WARP" || echo "")

    if [[ -z "$SUVR_CTX" || -z "$SUVR_WB" ]]; then
        echo "⚠️  [$SUBJ] Empty SUVR values — skipping"
        return
    fi

    mSUVr=$(echo "$SUVR_CTX / $SUVR_WB" | bc -l)
    echo "$SUBJ,$mSUVr" >> "$OUT_CSV"

    echo "✅ [$SUBJ] Done — mSUVr: $mSUVr"
}

# ============================================================
# Loop over all subjects
# ============================================================
echo "===================================================="
echo "🚀 Starting PET→T1 registration + mSUVr calculation"
echo "===================================================="

for SUBJ_DIR in "$BASE_DIR"/*; do
    if [[ -d "$SUBJ_DIR" ]]; then
        process_subject "$SUBJ_DIR" "$VOI_CTX" "$VOI_WB" "$BASE_DIR"
    fi
done

echo "===================================================="
echo "✅ All subjects processed — results: $OUT_CSV"
echo "===================================================="

