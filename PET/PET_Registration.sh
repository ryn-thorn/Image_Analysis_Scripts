#!/usr/bin/env bash
set -euo pipefail

# Paths
export pet=/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/PET/nii_wave2
export fs=/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/freesurfer/freesurfer_6.0/03_Analysis
export out=/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv/mSUVr_2025
export suv=/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv/florbetaben
export rois=${out}/target_rois.txt

# Function to process one subject
process_subject() {
    i=$1
    echo ">>> Processing subject $i"

    # Local scratch space (unique per subject & job)
    scratch=/tmp/IAM_${i}_$$
    mkdir -p "$out/${i}"

    # ---- Copy required inputs locally ----
    dcm2niix -o "$out/${i}"  -f %p "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/PET/dicom/IAM_${i}"/*CTAC*
    cp "$suv/IAM_${i}/SUV.nii" "$out/${i}/SUV.nii"

    # ---- Convert & preprocess ----
    mv "$out/${i}/Brain_MUSC.nii" "$out/${i}/CTAC.nii"
    rm -f "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/PET/dicom/${i}/Brain_MUSC.json"

    mrconvert -force "$fs/IAM_${i}/mri/T1.mgz" "$out/${i}/T1.nii"

    fslreorient2std "$out/${i}/CTAC.nii" "$out/${i}/CTAC_std.nii"
    fslreorient2std "$suv/IAM_${i}/SUV.nii" "$out/${i}/SUV_std.nii"

    # ---- Registration ----
    flirt -ref "$out/${i}/CTAC_std.nii.gz" -in "$out/${i}/SUV_std.nii.gz" -out "$out/${i}/SUV_2_CTAC.nii"
    flirt -ref "$out/${i}/T1.nii" -in "$out/${i}/CTAC_std.nii.gz" \
        -out "$out/${i}/CTAC_REG.nii.gz" -omat "$out/${i}/CTAC_2_T1.mat" \
        -dof 6 -cost mutualinfo -searchcost mutualinfo
    flirt -ref "$out/${i}/T1.nii" -in "$out/${i}/SUV_2_CTAC.nii.gz" \
        -out "$out/${i}/SUV_reg.nii.gz" -init "$out/${i}/CTAC_2_T1.mat" \
        -dof 6 -applyxfm

    fslmaths "$out/${i}/SUV_reg.nii.gz" -thr 0 "$out/${i}/SUV_reg_thr.nii.gz"

    # ---- ROI extraction ----
    fsmakeroi -o "$out/${i}" "$fs/IAM_${i}/mri/aparc+aseg.mgz" "$rois"

    # ---- Clean up ----
    echo ">>> Finished subject $i"
}

export -f process_subject
export fs out suv rois

# ---- Build subject list from $suv ----
subjects=$(
  for d in "$suv"/*/; do
    subj=$(basename "$d" | sed 's/^IAM_//')
    # Require SUV.nii to exist, and skip if $out/subj already exists
    if [[ -f "$suv/IAM_${subj}/SUV.nii" && ! -d "$out/${subj}" ]]; then
      echo "$subj"
    fi
  done
)

# ---- Run in parallel ----
parallel -j 4 process_subject ::: $subjects

