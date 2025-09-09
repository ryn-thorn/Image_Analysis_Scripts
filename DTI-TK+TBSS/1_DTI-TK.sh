#!/usr/bin/env bash
# 1_DTI-TK_Registration.sh
# Prepares DTI-TK input tensors and performs group registration
#
# Example usage:
#   ./1_DTI-TK_Registration.sh \
#       --input /path/to/dki_pydesigner \
#       --output /path/to/dti-tk \
#       --subjects sub-101 sub-104 sub-110 \
#       --bet-thr 0.25

set -euo pipefail

# --- Argument parsing ---
usage() {
    echo ""
    echo "Usage: $0 --input INPUT_DIR --output OUTPUT_DIR [--subjects subj1 subj2 ...] [--bet-thr FLOAT]"
    echo ""
    echo "Required arguments:"
    echo "  --input     Path to input directory containing subject subfolders"
    echo "  --output    Path to output directory (derivatives root)"
    echo ""
    echo "Optional arguments:"
    echo "  --subjects  One or more subject IDs (default: auto-detect all in input)"
    echo "  --bet-thr   BET threshold (default: 0.2; higher = more aggressive skull stripping)"
    echo ""
    exit 1
}

INPUT=""
OUTPUT=""
SUBJECTS=()
BET_THR=0.2   # default

while [[ $# -gt 0 ]]; do
    case $1 in
        --input) INPUT=$2; shift 2 ;;
        --output) OUTPUT=$2; shift 2 ;;
        --subjects) shift; while [[ $# -gt 0 && ! $1 =~ ^-- ]]; do SUBJECTS+=("$1"); shift; done ;;
        --bet-thr) BET_THR=$2; shift 2 ;;
        *) usage ;;
    esac
done

[[ -z "$INPUT" || -z "$OUTPUT" ]] && usage

LOGDIR="$OUTPUT/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/1_DTI-TK_Registration.log"

echo "Running 1_DTI-TK_Registration.sh" | tee "$LOGFILE"
echo "Input: $INPUT" | tee -a "$LOGFILE"
echo "Output: $OUTPUT" | tee -a "$LOGFILE"
echo "BET threshold: $BET_THR" | tee -a "$LOGFILE"

# --- Subject discovery ---
if [[ ${#SUBJECTS[@]} -eq 0 ]]; then
    echo "No subjects provided, auto-detecting..." | tee -a "$LOGFILE"
    SUBJECTS=($(ls "$INPUT"))
fi

echo "Subjects: ${SUBJECTS[*]}" | tee -a "$LOGFILE"

# --- Ensure tensor prep roots exist ---
TENSOR_ROOT="$OUTPUT/01_Tensor_Prep"
mkdir -p "$TENSOR_ROOT"

TENSOR_POOL="$OUTPUT/02_Tensors"
mkdir -p "$TENSOR_POOL"

# --- Main preprocessing loop ---
for subj in "${SUBJECTS[@]}"; do
    echo "Preprocessing subject $subj..." | tee -a "$LOGFILE"

    subj_in="$INPUT/$subj"
    subj_out="$TENSOR_ROOT/$subj"
    mkdir -p "$subj_out"

    # Copy all dwi_preprocessed* files
    shopt -s nullglob
    files=("$subj_in"/dwi_preprocessed*)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "WARNING: No dwi_preprocessed files found for $subj" | tee -a "$LOGFILE"
        continue
    fi
    cp "${files[@]}" "$subj_out/" 2>>"$LOGFILE"

    # --- Generate mean b0 for BET ---
    fslmaths "$subj_out/dwi_preprocessed.nii" -Tmean \
             "$subj_out/dwi_preprocessed_b0.nii" >>"$LOGFILE" 2>&1

    # --- BET on mean b0 with mask output ---
    if ! bet2 "$subj_out/dwi_preprocessed_b0.nii" \
              "$subj_out/dwi_preprocessed_bet" \
              -m -f "$BET_THR" >>"$LOGFILE" 2>&1; then
        echo "ERROR: BET failed for $subj" | tee -a "$LOGFILE"
        exit 1
    fi

    # Standardize mask filename
    mv "$subj_out/dwi_preprocessed_bet_mask.nii.gz" \
       "$subj_out/dwi_preprocessed_mask.nii.gz" || true
    gunzip -f "$subj_out/dwi_preprocessed_mask.nii.gz" || true

    # Unzip all nii.gz for compatibility with DTI-TK
    gunzip -f "$subj_out"/*.nii.gz || true

    # --- BET QC copy ---
    QC_DIR="$TENSOR_ROOT/BET_QC"
    mkdir -p "$QC_DIR"
    cp "$subj_out/dwi_preprocessed_bet.nii" "$QC_DIR/${subj}_dwi_preprocessed_bet.nii" || true
    cp "$subj_out/dwi_preprocessed_mask.nii" "$QC_DIR/${subj}_dwi_preprocessed_mask.nii" || true

    echo "QC BET outputs available in $QC_DIR" | tee -a "$LOGFILE"

    # --- dtifit ---
    dtifit --data="$subj_out/dwi_preprocessed.nii" \
           --out="$subj_out/dti" \
           --mask="$subj_out/dwi_preprocessed_mask.nii" \
           --bvecs="$subj_out/dwi_preprocessed.bvec" \
           --bvals="$subj_out/dwi_preprocessed.bval" \
           --save_tensor >>"$LOGFILE" 2>&1

    # --- fsl_to_dtitk ---
    (
        cd "$subj_out"
        fsl_to_dtitk dti >>"$LOGFILE" 2>&1
    )

    # Unzip again (DTI-TK needs uncompressed nii)
    gunzip -f "$subj_out"/*.nii.gz || true

    # --- Cleanup extraneous scalars ---
    for f in L1 L2 L3 MD MO S0 V1 V2 V3 FA; do
        rm -f "$subj_out/dti_${f}.nii"*
    done

    # --- Copy + rename tensor into 02_Tensors ---
    if [[ -f "$subj_out/dti_tensor.nii" ]]; then
        cp "$subj_out/dti_tensor.nii" "$TENSOR_POOL/${subj}_dti_tensor.nii"
    else
        echo "ERROR: Missing dti_tensor.nii for $subj" | tee -a "$LOGFILE"
        exit 1
    fi

    echo "Finished preprocessing subject $subj" | tee -a "$LOGFILE"
done

# =======================================================================================
# DTI-TK Registration
# =======================================================================================
echo "Starting DTI-TK Registration..." | tee -a "$LOGFILE"

cd "$TENSOR_POOL"

# Make subject list file for DTI-TK
ls *_dti_tensor.nii > subjs.txt

# Step 0: Create mean_initial
TVMean -in subjs.txt -out mean_initial.nii.gz
TVResample -in mean_initial.nii.gz -align center -size 128 128 64 -vsize 1.5 1.75 2.25

# Step 1: Affine alignment
dti_affine_population mean_initial.nii.gz subjs.txt EDS 3 >>"$LOGFILE" 2>&1

# Step 2: Diffeomorphic alignment
TVtool -in mean_affine3.nii.gz -tr
BinaryThresholdImageFilter mean_affine3_tr.nii.gz mask.nii.gz 0.01 100 1 0
dti_diffeomorphic_population mean_affine3.nii.gz subjs_aff.txt mask.nii.gz 0.002 >>"$LOGFILE" 2>&1

echo "DTI-TK Registration complete!" | tee -a "$LOGFILE"
