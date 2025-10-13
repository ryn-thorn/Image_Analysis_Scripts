#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Usage
# ============================================================
# ./pet_to_t1_registration_single_skip.sh <base_dir> <voi_dir> <output_dir>
#
# Example:
#   ./pet_to_t1_registration_single_skip.sh \
#       /data/PET_subjects \
#       /path/to/Centiloid_Std_VOI/nifti/1mm \
#       /data/output
# ============================================================

BASE_DIR=$1
VOI_DIR=$2
OUTDIR=$3

mkdir -p "$OUTDIR"
OUT_CSV="$OUTDIR/mSUVr_all_subjects.csv"
echo "subject,mSUVr" > "$OUT_CSV"

VOI_CTX=$(ls "$VOI_DIR"/*voi_ctx_1mm.nii* 2>/dev/null | head -n1 || true)
VOI_WB=$(ls "$VOI_DIR"/*voi_WhlCblBrnStm_1mm.nii* 2>/dev/null | head -n1 || true)

# ============================================================
# Function: process one subject
# ============================================================
process_subject() {
    SUBJ_DIR="$1"
    VOI_CTX="$2"
    VOI_WB="$3"
    OUTDIR="$4"

    SUBJ=$(basename "$SUBJ_DIR")
    echo ""
    echo "===================================================="
    echo ">>> [$SUBJ] Starting processing"
    echo "===================================================="

    SUV=$(ls "$SUBJ_DIR"/SUV.nii* 2>/dev/null | head -n1 || true)
    CTAC=$(ls "$SUBJ_DIR"/CTAC.nii* 2>/dev/null | head -n1 || true)
    T1=$(ls "$SUBJ_DIR"/T1.nii* 2>/dev/null | head -n1 || true)

    if [[ ! -f "$SUV" || ! -f "$T1" ]]; then
        echo "⚠️ [$SUBJ] Missing SUV or T1 — skipping"
        return
    fi

    SUBJ_OUT="$OUTDIR/$SUBJ"
    mkdir -p "$SUBJ_OUT"

    # ------------------------------------------------------------
    # 1. Reorient
    # ------------------------------------------------------------
    if [[ -s "$SUBJ_OUT/SUV_reorient.nii.gz" && -s "$SUBJ_OUT/T1_reorient.nii.gz" ]]; then
        echo "🟡 [$SUBJ] Reorient outputs exist — skipping"
    else
        echo "🔄 [$SUBJ] Running fslreorient2std..."
        fslreorient2std "$SUV" "$SUBJ_OUT/SUV_reorient.nii.gz"
        [[ -n "$CTAC" ]] && fslreorient2std "$CTAC" "$SUBJ_OUT/CTAC_reorient.nii.gz"
        fslreorient2std "$T1" "$SUBJ_OUT/T1_reorient.nii.gz"
    fi

    # ------------------------------------------------------------
    # 2. Linear registration (flirt)
    # ------------------------------------------------------------
    if [[ -s "$SUBJ_OUT/SUV_in_T1_affine.nii.gz" && -s "$SUBJ_OUT/SUV_to_T1_affine.mat" ]]; then
        echo "🟡 [$SUBJ] Affine registration exists — skipping"
    else
        echo "🔄 [$SUBJ] Running FLIRT (affine)..."
        flirt -in "$SUBJ_OUT/SUV_reorient.nii.gz" \
              -ref "$SUBJ_OUT/T1_reorient.nii.gz" \
              -omat "$SUBJ_OUT/SUV_to_T1_affine.mat" \
              -out "$SUBJ_OUT/SUV_in_T1_affine.nii.gz" \
              -dof 6 -cost mutualinfo
    fi

    # ------------------------------------------------------------
    # 3. Nonlinear registration (fnirt)
    # ------------------------------------------------------------
    if [[ -s "$SUBJ_OUT/SUV_in_T1_fnirt.nii.gz" && -s "$SUBJ_OUT/SUV_to_T1_warpcoef" ]]; then
        echo "🟡 [$SUBJ] FNIRT outputs exist — skipping"
    else
        echo "🔄 [$SUBJ] Running FNIRT..."
        fnirt --in="$SUBJ_OUT/SUV_reorient.nii.gz" \
              --aff="$SUBJ_OUT/SUV_to_T1_affine.mat" \
              --cout="$SUBJ_OUT/SUV_to_T1_warpcoef" \
              --iout="$SUBJ_OUT/SUV_in_T1_fnirt.nii.gz" \
              --ref="$SUBJ_OUT/T1_reorient.nii.gz" \
              --lambda=300 \
              --intmod=global_linear
    fi

    # ------------------------------------------------------------
    # 4. Warp VOIs
    # ------------------------------------------------------------
    if [[ -s "$SUBJ_OUT/voi_ctx_in_T1.nii.gz" && -s "$SUBJ_OUT/voi_WB_in_T1.nii.gz" ]]; then
        echo "🟡 [$SUBJ] Warped VOIs exist — skipping"
    else
        echo "🔄 [$SUBJ] Applying warp to VOIs..."
        applywarp --in="$VOI_CTX" \
                  --ref="$SUBJ_OUT/T1_reorient.nii.gz" \
                  --warp="$SUBJ_OUT/SUV_to_T1_warpcoef" \
                  --out="$SUBJ_OUT/voi_ctx_in_T1.nii.gz" \
                  --interp=nn

        applywarp --in="$VOI_WB" \
                  --ref="$SUBJ_OUT/T1_reorient.nii.gz" \
                  --warp="$SUBJ_OUT/SUV_to_T1_warpcoef" \
                  --out="$SUBJ_OUT/voi_WB_in_T1.nii.gz" \
                  --interp=nn
    fi

    # ------------------------------------------------------------
    # 5. Compute mSUVr
    # ------------------------------------------------------------
    if grep -q "^$SUBJ," "$OUTDIR/mSUVr_all_subjects.csv"; then
        echo "🟡 [$SUBJ] mSUVr already computed — skipping"
    else
        echo "🔄 [$SUBJ] Computing mSUVr..."
        SUVR_CTX=$(fslmeants -i "$SUBJ_OUT/SUV_in_T1_fnirt.nii.gz" -m "$SUBJ_OUT/voi_ctx_in_T1.nii.gz" || echo "")
        SUVR_WB=$(fslmeants -i "$SUBJ_OUT/SUV_in_T1_fnirt.nii.gz" -m "$SUBJ_OUT/voi_WB_in_T1.nii.gz" || echo "")

        if [[ -z "$SUVR_CTX" || -z "$SUVR_WB" ]]; then
            echo "⚠️ [$SUBJ] Empty SUVR values — skipping"
            return
        fi

        mSUVr=$(echo "$SUVR_CTX / $SUVR_WB" | bc -l)
        echo "$SUBJ,$mSUVr" >> "$OUTDIR/mSUVr_all_subjects.csv"
        echo "✅ [$SUBJ] Done — mSUVr: $mSUVr"
    fi
}

# ============================================================
# Loop over subjects
# ============================================================
echo "Processing all subjects sequentially..."
for SUBJ_DIR in "$BASE_DIR"/*; do
    if [[ -d "$SUBJ_DIR" ]]; then
        process_subject "$SUBJ_DIR" "$VOI_CTX" "$VOI_WB" "$OUTDIR"
    fi
done

echo "===================================================="
echo "✅ All subjects processed — results: $OUT_CSV"
echo "===================================================="
