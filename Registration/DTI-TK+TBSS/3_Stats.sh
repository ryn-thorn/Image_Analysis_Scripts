#!/usr/bin/env bash
# 3_Stats.sh
# Warps ROI atlases into DTI-TK template space and extracts ROI stats (mean + median)
#
# Example usage:
#   ./3_Stats.sh \
#       --input /path/to/derivatives/dti-tk_test \
#       --output /path/to/derivatives/dti-tk_test \
#       --rois /path/to/atlas.nii.gz \
#       --lut /path/to/atlas_lut.txt \
#       --subjects sub-101 sub-104 \
#       --wmmets

set -euo pipefail

# --- Argument parsing ---
usage() {
    echo ""
    echo "Usage: $0 --input INPUT_DIR --output OUTPUT_DIR --rois ROI_ATLAS --lut ROI_LUT [--subjects subj1 subj2 ...] [--wmmets]"
    echo ""
    echo "Required arguments:"
    echo "  --input     Path to derivatives root (must contain 01_Tensor_Prep, 02_Tensors)"
    echo "  --output    Path to derivatives root (stats go in 03_Stats)"
    echo "  --rois      ROI atlas image(s) to warp into template space"
    echo "  --lut       Lookup table (2-column text: ROI_index ROI_name)"
    echo ""
    echo "Optional arguments:"
    echo "  --subjects  One or more subject IDs (default: auto-detect from 01_Tensor_Prep)"
    echo "  --wmmets    Include WM metrics in addition to dmets"
    echo ""
    exit 1
}

INPUT=""
OUTPUT=""
ROIS=()
LUT=""
SUBJECTS=()
INCLUDE_WMMETS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --input) INPUT=$2; shift 2 ;;
        --output) OUTPUT=$2; shift 2 ;;
        --rois) shift; while [[ $# -gt 0 && ! $1 =~ ^-- ]]; do ROIS+=("$1"); shift; done ;;
        --lut) LUT=$2; shift 2 ;;
        --subjects) shift; while [[ $# -gt 0 && ! $1 =~ ^-- ]]; do SUBJECTS+=("$1"); shift; done ;;
        --wmmets) INCLUDE_WMMETS=true; shift ;;
        *) usage ;;
    esac
done

[[ -z "$INPUT" || -z "$OUTPUT" || ${#ROIS[@]} -eq 0 || -z "$LUT" ]] && usage

LOGDIR="$OUTPUT/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/3_Stats.log"

echo "Running 3_Stats.sh" | tee "$LOGFILE"
echo "Input: $INPUT" | tee -a "$LOGFILE"
echo "Output: $OUTPUT" | tee -a "$LOGFILE"
echo "ROIs: ${ROIS[*]}" | tee -a "$LOGFILE"
echo "LUT: $LUT" | tee -a "$LOGFILE"
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

# --- Stats root ---
STATS_ROOT="$OUTPUT/03_Stats"
mkdir -p "$STATS_ROOT"

# =======================================================================================
# Step 1: Warp ROI atlases into template space
# =======================================================================================
WARPED_ROIS=()
ATLAS_DIR="$STATS_ROOT/Atlases"
mkdir -p "$ATLAS_DIR"

for roi in "${ROIS[@]}"; do
    base=$(basename "$roi" .nii.gz)
    out_atlas="$ATLAS_DIR/${base}_in_template.nii.gz"
    echo "Warping ROI atlas $roi -> $out_atlas" | tee -a "$LOGFILE"
    deformable_reg "$roi" "$INPUT/02_Tensors/dtitk_template.nii" "$out_atlas" >>"$LOGFILE" 2>&1
    WARPED_ROIS+=("$out_atlas")
done

# =======================================================================================
# Step 2: Extract ROI stats (mean + median) for each metric
# =======================================================================================
for met in "${metrics[@]}"; do
    echo "Processing metric: $met" | tee -a "$LOGFILE"

    OUTCSV="$STATS_ROOT/roi_${met}_stats.csv"

    # Header row
    header="subject"
    while read -r idx name; do
        header+=",${name}_mean,${name}_median"
    done < "$LUT"
    echo "$header" > "$OUTCSV"

    # Per-subject rows
    for subj in "${SUBJECTS[@]}"; do
        subj_met="$TENSOR_ROOT/$subj/dti_tensor_in_template_${met}.nii"
        if [[ ! -f "$subj_met" ]]; then
            echo "WARNING: Missing $met for $subj ($subj_met)" | tee -a "$LOGFILE"
            continue
        fi

        row="$subj"
        while read -r idx name; do
            mean=$(fslstats "$subj_met" -k "$WARPED_ROIS" -l $(($idx-1)) -u $idx -M 2>/dev/null || echo "NA")
            median=$(fslstats "$subj_met" -k "$WARPED_ROIS" -l $(($idx-1)) -u $idx -P 50 2>/dev/null || echo "NA")
            row+=",$mean,$median"
        done < "$LUT"

        echo "$row" >> "$OUTCSV"
    done

    echo "Saved $OUTCSV" | tee -a "$LOGFILE"
done

echo "ROI stats extraction complete!" | tee -a "$LOGFILE"
