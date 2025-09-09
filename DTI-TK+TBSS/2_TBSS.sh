#!/usr/bin/env bash
# 2_TBSS.sh
# Performs TBSS analysis on registered diffusion metrics
#
# Example usage:
#   ./2_TBSS.sh \
#       --input /path/to/derivatives/dti-tk \
#       --output /path/to/derivatives/tbss \
#       --subjects sub-101 sub-104 sub-110 \
#       --wmmets
#
# Notes:
#   - FA is processed through the full TBSS pipeline (tbss_1..tbss_4).
#   - All other metrics are projected onto the FA skeleton using tbss_non_FA.

set -euo pipefail

# --- Argument parsing ---
usage() {
    echo ""
    echo "Usage: $0 --input INPUT_DIR --output OUTPUT_DIR [--subjects subj1 subj2 ...] [--wmmets]"
    echo ""
    echo "Required arguments:"
    echo "  --input     Path to derivatives root (must contain 01_Tensor_Prep)"
    echo "  --output    Path to derivatives root (TBSS results will go in 02_TBSS)"
    echo ""
    echo "Optional arguments:"
    echo "  --subjects  One or more subject IDs (default: auto-detect from 01_Tensor_Prep)"
    echo "  --wmmets    Include white matter metrics in addition to default dmets"
    echo ""
    exit 1
}

INPUT=""
OUTPUT=""
SUBJECTS=()
INCLUDE_WMMETS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --input) INPUT=$2; shift 2 ;;
        --output) OUTPUT=$2; shift 2 ;;
        --subjects) shift; while [[ $# -gt 0 && ! $1 =~ ^-- ]]; do SUBJECTS+=("$1"); shift; done ;;
        --wmmets) INCLUDE_WMMETS=true; shift ;;
        *) usage ;;
    esac
done

[[ -z "$INPUT" || -z "$OUTPUT" ]] && usage

LOGDIR="$OUTPUT/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/2_TBSS.log"

echo "Running 2_TBSS.sh" | tee "$LOGFILE"
echo "Input: $INPUT" | tee -a "$LOGFILE"
echo "Output: $OUTPUT" | tee -a "$LOGFILE"
echo "Include WM metrics: $INCLUDE_WMMETS" | tee -a "$LOGFILE"

# --- Subject discovery ---
TENSOR_ROOT="$INPUT/01_Tensor_Prep"
if [[ ${#SUBJECTS[@]} -eq 0 ]]; then
    echo "No subjects provided, auto-detecting from $TENSOR_ROOT..." | tee -a "$LOGFILE"
    SUBJECTS=($(ls "$TENSOR_ROOT"))
fi
echo "Subjects: ${SUBJECTS[*]}" | tee -a "$LOGFILE"

# --- Metric lists ---
dmets=("dti_ad" "dti_rd" "dti_md" "dti_fa" "dki_ak" "dki_rk" "dki_mk")
wmmets=("wmti_eas_rd" "wmti_awf")

metrics=("${dmets[@]}")
if $INCLUDE_WMMETS; then
    metrics+=("${wmmets[@]}")
fi

# --- TBSS root ---
TBSS_ROOT="$OUTPUT/02_TBSS"
mkdir -p "$TBSS_ROOT"
cd "$TBSS_ROOT"

# =======================================================================================
# Step 1: FA full TBSS pipeline
# =======================================================================================
echo "Preparing FA images..." | tee -a "$LOGFILE"
FA_DIR="$TBSS_ROOT/FA_input"
mkdir -p "$FA_DIR"

for subj in "${SUBJECTS[@]}"; do
    fa_in="$TENSOR_ROOT/$subj/dti_tensor_in_template_fa.nii"
    if [[ ! -f "$fa_in" ]]; then
        echo "ERROR: Missing FA image for $subj ($fa_in)" | tee -a "$LOGFILE"
        exit 1
    fi
    cp "$fa_in" "$FA_DIR/${subj}_fa.nii"
done

echo "Running TBSS pipeline on FA..." | tee -a "$LOGFILE"
tbss_1_preproc "$FA_DIR"/*.nii >>"$LOGFILE" 2>&1
tbss_2_reg -T >>"$LOGFILE" 2>&1
tbss_3_postreg -S >>"$LOGFILE" 2>&1
tbss_4_prestats 0.2 >>"$LOGFILE" 2>&1

# =======================================================================================
# Step 2: Project other metrics onto FA skeleton
# =======================================================================================
for met in "${metrics[@]}"; do
    [[ "$met" == "dti_fa" ]] && continue  # already handled

    echo "Processing metric: $met" | tee -a "$LOGFILE"
    MET_DIR="$TBSS_ROOT/${met}_input"
    mkdir -p "$MET_DIR"

    for subj in "${SUBJECTS[@]}"; do
        met_in="$TENSOR_ROOT/$subj/dti_tensor_in_template_${met}.nii"
        if [[ ! -f "$met_in" ]]; then
            echo "WARNING: Missing $met for $subj ($met_in)" | tee -a "$LOGFILE"
            continue
        fi
        cp "$met_in" "$MET_DIR/${subj}_${met}.nii"
    done

    echo "Running tbss_non_FA for $met..." | tee -a "$LOGFILE"
    tbss_non_FA "$MET_DIR"/*.nii >>"$LOGFILE" 2>&1
done

echo "TBSS pipeline complete!" | tee -a "$LOGFILE"
