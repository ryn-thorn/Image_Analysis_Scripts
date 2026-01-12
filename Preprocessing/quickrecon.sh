#!/bin/bash
set -euo pipefail

# Subjects to process
SUBJECTS=(1204 1218 1219 1220 1224 1229)

# Base paths
RAW_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS"
FS_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/Preprocessing/freesurfer/freesurfer_6.0"

# FreeSurfer needs SUBJECTS_DIR set
export SUBJECTS_DIR="${FS_BASE}"

for SUB in "${SUBJECTS[@]}"; do
    echo "========================================"
    echo "Running recon-all for subject ${SUB}"
    echo "========================================"

    T1="${RAW_BASE}/sub-${SUB}/ses-Y0/anat/sub-${SUB}_ses-Y0_T1w.nii.gz"
    OUTDIR="${FS_BASE}/sub-${SUB}/ses-Y0"

    if [[ ! -f "${T1}" ]]; then
        echo "ERROR: T1 not found for sub-${SUB}"
        echo "  Expected: ${T1}"
        continue
    fi

    mkdir -p "${OUTDIR}"

    recon-all \
        -subject "sub-${SUB}_ses-Y0" \
        -sd "${FS_BASE}" \
        -i "${T1}" \
        -all
done
