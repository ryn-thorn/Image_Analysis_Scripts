#!/bin/bash
# ------------------------------------------------------------------
# Extract bilateral subcortical ROIs from multiple Freesurfer recon-all outputs
# Skips subjects if ROIs already exist
# ------------------------------------------------------------------
# Usage:
#   ./1_fs-sc-roi-isolation.sh /path/to/fs_base
# ------------------------------------------------------------------

if [ $# -ne 1 ]; then
  echo "Usage: $0 /path/to/fs_base"
  exit 1
fi

fs_base="$1"

# ROI names and IDs (parallel arrays for bash 3 compatibility)
roi_names=(
  Left-Thalamus-Proper Left-Caudate Left-Putamen Left-Pallidum
  Left-Hippocampus Left-Amygdala Left-Accumbens-area Left-VentralDC
  Right-Thalamus-Proper Right-Caudate Right-Putamen Right-Pallidum
  Right-Hippocampus Right-Amygdala Right-Accumbens-area Right-VentralDC
)

roi_ids=(10 11 12 13 17 18 26 28 49 50 51 52 53 54 58 60)

# Loop through all subject folders in fs_base
for subj_dir in "$fs_base"/*; do
    [ -d "$subj_dir" ] || continue  # skip if not a directory
    subj_name=$(basename "$subj_dir")
    aseg="$subj_dir/mri/aseg.mgz"
    outdir="$subj_dir/sb-rois"

    if [ ! -f "$aseg" ]; then
        echo "Skipping $subj_name: aseg.mgz not found."
        continue
    fi

    # Skip if ROIs already exist
    if [ -d "$outdir" ] && [ "$(ls -A "$outdir"/*.nii.gz 2>/dev/null)" ]; then
        echo "Skipping $subj_name: ROIs already exist."
        continue
    fi

    mkdir -p "$outdir"
    echo "Extracting subcortical ROIs for subject: $subj_name"

    for i in "${!roi_names[@]}"; do
        roi_name=${roi_names[$i]}
        roi_id=${roi_ids[$i]}
        out_mgz="$outdir/${roi_name}.mgz"
        out_nii="$outdir/${roi_name}.nii.gz"

        echo "  -> $roi_name"
        # Extract ROI from aseg
        mri_binarize --i "$aseg" --match $roi_id --o "$out_mgz" --binval 1

        # Convert to NIfTI
        mri_convert "$out_mgz" "$out_nii" >/dev/null 2>&1

        # Remove the mgz version
        rm -f "$out_mgz"
    done

    echo "ROIs saved to: $outdir/"
done

echo "All subjects processed!"
