#!/usr/bin/env bash

# =====================================
# USER SETTINGS
# =====================================
MAINDIR="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/Segmentation/native_subcortical_roi_analysis/fsl-only"

OUTCSV="${MAINDIR}/all_voxel_counts.csv"

ROIS=(
  L_Thal L_Caud L_Puta L_Pall L_Hipp L_Amyg L_Accu
  R_Thal R_Caud R_Puta R_Pall R_Hipp R_Amyg R_Accu
)

# =====================================
# INITIALIZE OUTPUT
# =====================================
echo "sub,ses,roi,t1_unmasked_voxels,t1_gm_masked_voxels,t1_csf_masked_voxels,b0_unmasked_voxels,b0_gm_masked_voxels,b0_csf_masked_voxels" > "${OUTCSV}"

# =====================================
# FUNCTIONS
# =====================================
count_voxels () {
  local img="$1"
  fslstats "${img}" -V | awk '{print $1}'
}

# =====================================
# MAIN LOOP
# =====================================
for SUBDIR in "${MAINDIR}"/sub-*; do
  [[ -d "${SUBDIR}" ]] || continue
  SUB=$(basename "${SUBDIR}")

  for SESDIR in "${SUBDIR}"/ses-*; do
    [[ -d "${SESDIR}" ]] || continue
    SES=$(basename "${SESDIR}")

    # Skip empty session folders
    shopt -s nullglob
    FILES=("${SESDIR}"/*.nii.gz)
    shopt -u nullglob
    [[ ${#FILES[@]} -eq 0 ]] && continue

    echo "Processing ${SUB} ${SES}"

    for ROI in "${ROIS[@]}"; do

      # ==========================
      # T1 SPACE
      # ==========================
      T1_ROI="${SESDIR}/${ROI}.nii.gz"
      T1_GM="${SESDIR}/synthstrip_seg_1.nii.gz"
      T1_CSF="${SESDIR}/synthstrip_seg_0.nii.gz"

      if [[ -f "${T1_ROI}" && -f "${T1_GM}" && -f "${T1_CSF}" ]]; then

        T1_UNMASKED=$(count_voxels "${T1_ROI}")

        T1_GM_TMP=$(mktemp "${SESDIR}/tmp_${SUB}_${SES}_${ROI}_T1_GM_XXXX.nii.gz")
        fslmaths "${T1_ROI}" -mul "${T1_GM}" -bin "${T1_GM_TMP}"
        T1_GM_COUNT=$(count_voxels "${T1_GM_TMP}")
        rm -f "${T1_GM_TMP}"

        # ROI == 1 AND CSF == 0
        T1_CSF_TMP=$(mktemp "${SESDIR}/tmp_${SUB}_${SES}_${ROI}_T1_notCSF_XXXX.nii.gz")
        fslmaths "${T1_ROI}" -mul "${T1_CSF}" -bin -sub "${T1_ROI}" -abs "${T1_CSF_TMP}"
        T1_CSF_COUNT=$(count_voxels "${T1_CSF_TMP}")
        rm -f "${T1_CSF_TMP}"

      else
        T1_UNMASKED=NA
        T1_GM_COUNT=NA
        T1_CSF_COUNT=NA
      fi

      # ==========================
      # B0 SPACE
      # ==========================
      B0_ROI="${SESDIR}/${ROI}_B0.nii.gz"
      B0_GM="${SESDIR}/GM_B0.nii.gz"
      B0_CSF="${SESDIR}/CSF_B0.nii.gz"

      if [[ -f "${B0_ROI}" && -f "${B0_GM}" && -f "${B0_CSF}" ]]; then

        B0_UNMASKED=$(count_voxels "${B0_ROI}")

        B0_GM_TMP=$(mktemp "${SESDIR}/tmp_${SUB}_${SES}_${ROI}_B0_GM_XXXX.nii.gz")
        fslmaths "${B0_ROI}" -mul "${B0_GM}" -bin "${B0_GM_TMP}"
        B0_GM_COUNT=$(count_voxels "${B0_GM_TMP}")
        rm -f "${B0_GM_TMP}"

        # ROI == 1 AND CSF == 0
        B0_CSF_TMP=$(mktemp "${SESDIR}/tmp_${SUB}_${SES}_${ROI}_B0_notCSF_XXXX.nii.gz")
        fslmaths "${B0_ROI}" -mul "${B0_CSF}" -bin -sub "${B0_ROI}" -abs "${B0_CSF_TMP}"
        B0_CSF_COUNT=$(count_voxels "${B0_CSF_TMP}")
        rm -f "${B0_CSF_TMP}"

      else
        B0_UNMASKED=NA
        B0_GM_COUNT=NA
        B0_CSF_COUNT=NA
      fi

      # ==========================
      # WRITE ROW
      # ==========================
      echo "${SUB},${SES},${ROI},${T1_UNMASKED},${T1_GM_COUNT},${T1_CSF_COUNT},${B0_UNMASKED},${B0_GM_COUNT},${B0_CSF_COUNT}" >> "${OUTCSV}"

    done
  done
done

echo "====================================="
echo "All done!"
echo "Output written to:"
echo "${OUTCSV}"