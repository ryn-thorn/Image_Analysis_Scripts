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
    t1_nii="$subj_out/T1.nii"

    if [ ! -f "$t1_mgz" ]; then
        echo "T1.mgz not found for $subj_name, skipping..."
        continue
    fi

    if [ ! -f "$t1_nii" ]; then
        echo "Converting and reorienting T1 for $subj_name..."
        mri_convert "$t1_mgz" "$t1_nii"
        fslreorient2std "$t1_nii" "$t1_nii"
    else
        echo "T1.nii already exists, skipping conversion."
    fi

    # ---- Step 2: Create 3D mean of DWI ----
    dwi_file="$pyd_base/$subj_name/dwi_preprocessed.nii.gz"
    dwi_3d="$subj_out/dwi_mean.nii.gz"

    if [ ! -f "$dwi_file" ]; then
        echo "DWI not found for $subj_name, skipping..."
        continue
    fi

    if [ ! -f "$dwi_3d" ]; then
        echo "Creating 3D mean DWI for $subj_name..."
        fslmaths "$dwi_file" -Tmean "$dwi_3d"
    else
        echo "dwi_mean.nii.gz already exists, skipping."
    fi

    # ---- Step 3: Register T1 to DWI space ----
    t1_in_dwi="$subj_out/T1_in_dwi.nii"
    t1_to_dwi_mat="$subj_out/T1_to_dwi.mat"

    if [ ! -f "$t1_in_dwi" ] || [ ! -f "$t1_to_dwi_mat" ]; then
        echo "Registering T1 to DWI for $subj_name..."
        flirt -in "$t1_nii" -ref "$dwi_3d" -out "$t1_in_dwi" -omat "$t1_to_dwi_mat"
    else
        echo "T1_to_DWI registration already exists, skipping."
    fi

    # ---- Step 4: Apply transform to ROIs ----
    roi_dir="$subj/sb-rois"
    if [ ! -d "$roi_dir" ]; then
        echo "No ROI directory found for $subj_name, skipping ROI transformation..."
        continue
    fi

    roi_files=("$roi_dir"/*.nii*)
    if [ ${#roi_files[@]} -eq 0 ]; then
        echo "No ROI files found in $roi_dir, skipping ROI transformation..."
        continue
    fi

    for roi in "${roi_files[@]}"; do
        [ -f "$roi" ] || continue
        roi_name=$(basename "$roi")
        roi_out="$subj_out/$roi_name"

        if [ ! -f "$roi_out" ]; then
            echo "Applying transform to ROI $roi_name..."
            flirt -in "$roi" -ref "$dwi_3d" -applyxfm -init "$t1_to_dwi_mat" -out "$roi_out"
        else
            echo "$roi_name already transformed, skipping."
        fi
    done

    # ---- Step 5: Threshold ROIs based on MD and FA ----
    md_file="$pyd_base/$subj_name/metrics/dti_md.nii.gz"
    fa_file="$pyd_base/$subj_name/metrics/dti_fa.nii.gz"
    thr_mask="$subj_out/thr_mask.nii.gz"

    if [ ! -f "$md_file" ] || [ ! -f "$fa_file" ]; then
        echo "MD or FA file missing for $subj_name, skipping thresholding..."
        continue
    fi

    if [ ! -f "$thr_mask" ]; then
        echo "Creating threshold mask for $subj_name..."
        /opt/anaconda3/bin/python <<EOF
import nibabel as nib
import numpy as np

md_img = nib.load("$md_file")
fa_img = nib.load("$fa_file")

md_data = md_img.get_fdata()
fa_data = fa_img.get_fdata()

mask_data = (md_data <= 1.5) & (fa_data <= 0.4)
mask_img = nib.Nifti1Image(mask_data.astype(np.uint8), md_img.affine, md_img.header)
nib.save(mask_img, "$thr_mask")
EOF
    else
        echo "Threshold mask already exists, skipping."
    fi

    # ---- Step 6: Apply threshold mask to each ROI ----
    for roi in "$subj_out"/Left* "$subj_out"/Right* ; do
        #[ "$roi" != "$thr_mask" ] || continue
        echo "Thresholding $roi"
        roi_thr="${roi}_thr.nii.gz"
        if [ ! -f "$roi_thr" ]; then
            echo "Creating thresholded ROI: $(basename "$roi_thr")"
            fslmaths "$roi" -mul "$thr_mask" -bin "$roi_thr"
        else
            echo "$(basename "$roi_thr") already exists, skipping."
        fi
    done

done

echo "T1 to DKI registration and ROI thresholding finished successfully!"
