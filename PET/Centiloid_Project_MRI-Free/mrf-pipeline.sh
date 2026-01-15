#!/bin/bash
set -euo pipefail
shopt -s nullglob

# -----------------------------
# Single input folder only
# -----------------------------
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <INPUT_DIR>"
    exit 1
fi

INPUT_DIR=$1
CSV="${INPUT_DIR}/PET_ROI_values.csv"

# Hardcoded paths
MNI_TEMPLATE="/usr/local/fsl/data/standard/MNI152_T1_1mm.nii.gz"
ROI_CTX="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/centiloids_mri-free/Centiloid_Std_VOI/nifti/1mm/voi_ctx_1mm.nii"
ROI_WHL="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/centiloids_mri-free/Centiloid_Std_VOI/nifti/1mm/voi_WhlCbl_1mm.nii"

echo "Subj,Tracer,CTX,WHL" > "${CSV}"

echo "========== PET normalization + ROI extraction =========="

# Loop over subjects
for SUBJ_PATH in "${INPUT_DIR}"/*/; do
    SUBJ=$(basename "${SUBJ_PATH}")
    echo "----- ${SUBJ} -----"

    for PET in PiB florbetapir; do

        PET_IN="${SUBJ_PATH}/${PET}.nii.gz"
        [[ ! -f "${PET_IN}" ]] && continue

        PET_3D="${SUBJ_PATH}/${PET}_vol0.nii.gz"
        PET_FLIRT="${SUBJ_PATH}/${PET}_FLIRT_to_MNI.nii.gz"
        PET_AFFINE="${SUBJ_PATH}/${PET}_to_MNI_affine.mat"
        PET_FNIRT="${SUBJ_PATH}/${PET}_FNIRT_to_MNI.nii.gz"
        PET_WARP="${SUBJ_PATH}/${PET}_warp.nii.gz"
        FNIRT_LOG="${SUBJ_PATH}/${PET}_fnirt.log"

        # ---------- 4D → 3D ----------
        if [[ ! -f "${PET_3D}" ]]; then
            fslroi "${PET_IN}" "${PET_3D}" 0 1
        fi

        # ---------- FLIRT ----------
        if [[ ! -f "${PET_FLIRT}" ]]; then
            flirt \
                -in "${PET_3D}" \
                -ref "${MNI_TEMPLATE}" \
                -out "${PET_FLIRT}" \
                -omat "${PET_AFFINE}"
        fi

		# ---------- FNIRT (skip on failure) ----------
		if [[ ! -f "${PET_FNIRT}" ]]; then
			set +e
			fnirt \
				--in="${PET_3D}" \
				--ref="${MNI_TEMPLATE}" \
				--aff="${PET_AFFINE}" \
				--cout="${PET_WARP}" \
				--iout="${PET_FNIRT}" \
				> "${FNIRT_LOG}" 2>&1
			FNIRT_STATUS=$?
			set -e
		
			if [[ ${FNIRT_STATUS} -ne 0 ]]; then
				echo "WARNING: FNIRT failed for ${SUBJ} ${PET}, skipping"
				continue
			fi
		fi


        # ---------- ROI resampling ----------
        ROI_CTX_RESAMP="${SUBJ_PATH}/voi_ctx_on_${PET}_grid.nii.gz"
        ROI_WHL_RESAMP="${SUBJ_PATH}/voi_whlcbl_on_${PET}_grid.nii.gz"

        if [[ ! -f "${ROI_CTX_RESAMP}" ]]; then
            flirt \
                -in "${ROI_CTX}" \
                -ref "${PET_FNIRT}" \
                -out "${ROI_CTX_RESAMP}" \
                -applyxfm -usesqform \
                -interp nearestneighbour
        fi

        if [[ ! -f "${ROI_WHL_RESAMP}" ]]; then
            flirt \
                -in "${ROI_WHL}" \
                -ref "${PET_FNIRT}" \
                -out "${ROI_WHL_RESAMP}" \
                -applyxfm -usesqform \
                -interp nearestneighbour
        fi

        # ---------- ROI extraction ----------
        CTX_VAL=$(fslmeants -i "${PET_FNIRT}" -m "${ROI_CTX_RESAMP}")
        WHL_VAL=$(fslmeants -i "${PET_FNIRT}" -m "${ROI_WHL_RESAMP}")

        echo "${SUBJ},${PET},${CTX_VAL},${WHL_VAL}" >> "${CSV}"

    done
done

echo "=========================================="
echo "DONE. CSV saved to ${CSV}"
echo "=========================================="
