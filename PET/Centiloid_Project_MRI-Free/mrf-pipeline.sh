#!/bin/bash
set -euo pipefail

# Usage:
# ./mrf-pipeline.sh [input_path] [output_path]

INPUT_DIR="$1"
OUTPUT_DIR="$2"

# MNI template
MNI_TEMPLATE="/usr/local/fsl/data/standard/MNI152_T1_1mm.nii.gz"

# ROI files
ROI_CTX="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/centiloids_mri-free/Centiloid_Std_VOI/nifti/1mm/voi_ctx_1mm.nii"
ROI_WHL="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/centiloids_mri-free/Centiloid_Std_VOI/nifti/1mm/voi_WhlCbl_1mm.nii"

mkdir -p "${OUTPUT_DIR}"

CSV="${OUTPUT_DIR}/PET_intensity_values.csv"
echo "subjID,pet,ctx,WhlCbl" > "${CSV}"

MERGE_LIST=()

echo "========== STEP 1: Linear registration to MNI =========="

for SUBJ_PATH in "${INPUT_DIR}"/*/; do
    SUBJ=$(basename "${SUBJ_PATH}")
    REGDIR="${SUBJ_PATH}/reg"
    mkdir -p "${REGDIR}"

    PIB_IN="${SUBJ_PATH}/PiB.nii.gz"
    [[ ! -f "${PIB_IN}" ]] && continue

    # Ensure 3D input
    PIB_3D="${REGDIR}/PiB_3d.nii.gz"
    if [[ ! -f "${PIB_3D}" ]]; then
        fslroi "${PIB_IN}" "${PIB_3D}" 0 1
    fi

    PIB_MNI="${REGDIR}/PiB_MNI.nii.gz"
    PIB_MAT="${REGDIR}/PiB_to_MNI.mat"

    if [[ ! -f "${PIB_MNI}" ]]; then
        flirt -in "${PIB_3D}" \
              -ref "${MNI_TEMPLATE}" \
              -out "${PIB_MNI}" \
              -omat "${PIB_MAT}"
    fi

    if [[ -f "${PIB_MNI}" ]]; then
        MERGE_LIST+=("${PIB_MNI}")
    fi
done

echo "========== STEP 2: Build group MNI mean =========="

AVG_MNI="${OUTPUT_DIR}/PET_MNI_mean.nii.gz"

if [[ ${#MERGE_LIST[@]} -eq 0 ]]; then
    echo "ERROR: No PiB_MNI files found — cannot build average."
    exit 1
fi

echo "Merging ${#MERGE_LIST[@]} PiB MNI images..."
fslmerge -t "${OUTPUT_DIR}/PET_MNI_4d.nii.gz" "${MERGE_LIST[@]}"
fslmaths "${OUTPUT_DIR}/PET_MNI_4d.nii.gz" -Tmean "${AVG_MNI}"

echo "========== STEP 3: FNIRT to group MNI mean =========="

for SUBJ_PATH in "${INPUT_DIR}"/*/; do
    SUBJ=$(basename "${SUBJ_PATH}")
    REGDIR="${SUBJ_PATH}/reg"

    PIB_3D="${REGDIR}/PiB_3d.nii.gz"
    PIB_MAT="${REGDIR}/PiB_to_MNI.mat"
    PIB_FNIRT="${REGDIR}/PiB_FNIRT_to_MNIaverage.nii.gz"
    PIB_WARP="${REGDIR}/PiB_warpcoef.nii.gz"

    [[ ! -f "${PIB_3D}" ]] && continue
    [[ ! -f "${PIB_MAT}" ]] && continue
    [[ -f "${PIB_FNIRT}" ]] && continue

    fnirt \
        --in="${PIB_3D}" \
        --aff="${PIB_MAT}" \
        --ref="${AVG_MNI}" \
        --iout="${PIB_FNIRT}" \
        --cout="${PIB_WARP}" \
        --logout="${REGDIR}/PiB_to_PET_MNI_mean.log"
done

echo "========== STEP 4: ROI extraction =========="

for SUBJ_PATH in "${INPUT_DIR}"/*/; do
    SUBJ=$(basename "${SUBJ_PATH}")
    REGDIR="${SUBJ_PATH}/reg"

    PIB_FNIRT="${REGDIR}/PiB_FNIRT_to_MNIaverage.nii.gz"
    [[ ! -f "${PIB_FNIRT}" ]] && continue

    CTX_VAL=$(fslmeants -i "${PIB_FNIRT}" -m "${ROI_CTX}")
    WHL_VAL=$(fslmeants -i "${PIB_FNIRT}" -m "${ROI_WHL}")

    echo "${SUBJ},PiB,${CTX_VAL},${WHL_VAL}" >> "${CSV}"
done

echo "========== DONE =========="
echo "CSV written to: ${CSV}"
