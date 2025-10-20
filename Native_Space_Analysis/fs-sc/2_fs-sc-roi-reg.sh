#!/bin/bash
set -e  # Exit on any error
set -u  # Treat unset variables as errors

#####################################################
# usage: 2_fs-sc-roi-reg.sh /path/to/pyd_base /path/to/fs_base /path/to/output
#####################################################

# ---------------------------
# Inputs
# ---------------------------
pyd_base="$1"
fs_base="$2"
output_base="$3"

# ---------------------------
# Create output folder
# ---------------------------
mkdir -p "$output_base"

# ---------------------------
# Loop through subjects in fs_base
# ---------------------------
for subj in "$fs_base"/*; do
    [ -d "$subj" ] || continue  # skip if not a directory
    subj_name=$(basename "$subj")
    echo "Processing subject: $subj_name"

    subj_out="$output_base/$subj_name"
    mkdir -p "$subj_out"

    # ---- Step 1: T1 conversion and reorientation ----
    t1_mgz="$subj/mri/T1.mgz"
    if [ ! -f "$t1_mgz" ]; then
        echo "T1.mgz not found for $subj_name, skipping..."
        continue
    fi

    t1_nii="$subj_out/T1.nii"
    mri_convert "$t1_mgz" "$t1_nii"
    fslreorient2std "$t1_nii" "$t1_nii"

    # ---- Step 2: Create 3D mean of DWI ----
    dwi_file="$pyd_base/$subj_name/dwi_preprocessed.nii.gz"
    if [ ! -f "$dwi_file" ]; then
        echo "DWI not found for $subj_name, skipping..."
        continue
    fi
    dwi_3d="$subj_out/dwi_mean.nii.gz"
    fslmaths "$dwi_file" -Tmean "$dwi_3d"

    # ---- Step 3: Register T1 to DWI space ----
    t1_in_dwi="$subj_out/T1_in_dwi.nii"
    flirt -in "$t1_nii" -ref "$dwi_3d" -out "$t1_in_dwi" -omat "$subj_out/T1_to_dwi.mat"

    # ---- Step 4: Apply transform to ROIs ----
    roi_dir="$fs_base/sb-rois"
    for roi in "$roi_dir"/*.nii*; do
        roi_name=$(basename "$roi")
        roi_out="$subj_out/$roi_name"
        flirt -in "$roi" -ref "$dwi_3d" -applyxfm -init "$subj_out/T1_to_dwi.mat" -out "$roi_out"
    done
done

echo "T1 to DKI reg finished successfully!"
