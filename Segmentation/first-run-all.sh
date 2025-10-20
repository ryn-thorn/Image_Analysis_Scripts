#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Usage
# ============================================
# ./run_first_subcortical.sh <t1_image> <output_dir>
#
# Example:
# ./run_first_subcortical.sh sub-01_T1w.nii.gz ./output

T1_IMAGE="$1"
OUTDIR="$2"

mkdir -p "$OUTDIR"
BASENAME=$(basename "$T1_IMAGE" .nii.gz)

# ============================================
# Run FIRST for all subcortical structures
# ============================================
echo "Running FIRST (all subcortical structures)..."

run_first_all \
  -i "$T1_IMAGE" \
  -o "$OUTDIR/${BASENAME}_first" \
  -s L_Hipp,R_Hipp,L_Amyg,R_Amyg,L_Thal,R_Thal,L_Caud,R_Caud,L_Puta,R_Puta,L_Pall,R_Pall,L_Accu,R_Accu \
  -b

# ============================================
# Output summary
# ============================================
echo
echo "FIRST segmentation complete!"
echo "Results in: $OUTDIR"
echo
echo "Key outputs:"
echo "  ${BASENAME}_first_all_fast_firstseg.nii.gz   -> All subcortical ROIs (label map)"
echo "  ${BASENAME}_first_all_fast_origsegs.nii.gz  -> Individual structure segmentations"
