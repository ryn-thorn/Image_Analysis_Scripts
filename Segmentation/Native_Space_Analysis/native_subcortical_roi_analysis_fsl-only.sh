#!/usr/bin/env bash
set -euo pipefail

#################################
# CHECK INPUT
#################################
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <BIDS_ROOT>"
  exit 1
fi

BIDS_ROOT="$1"

#################################
# DERIVATIVE PATHS
#################################
SEG_ROOT="${BIDS_ROOT}/derivatives/Segmentation/native_subcortical_roi_analysis/fsl-only"
DWI_ROOT="${BIDS_ROOT}/derivatives/Preprocessing/pydesigner/dki-pydesigner"

MEANS_CSV="${SEG_ROOT}/roi_means.csv"
VOXELS_CSV="${SEG_ROOT}/roi_voxels.csv"

mkdir -p "${SEG_ROOT}"

#################################
# ROI DEFINITIONS
#################################
ROIS=(
  "L_Thal:110"
  "L_Caud:111"
  "L_Puta:112"
  "L_Pall:113"
  "BrStem:116"
  "L_Hipp:117"
  "L_Amyg:118"
  "L_Accu:126"
  "R_Thal:149"
  "R_Caud:150"
  "R_Puta:151"
  "R_Pall:152"
  "R_Hipp:153"
  "R_Amyg:154"
  "R_Accu:158"
)

#################################
# METRICS
#################################
METRICS=(
  "dki_mk"
  "dti_fa"
  "dti_md"
)

#################################
# INITIALIZE CSVs
#################################
echo "sub,ses,metric,roi,mean" > "${MEANS_CSV}"
echo "sub,ses,roi,voxels,volume_mm3" > "${VOXELS_CSV}"

#################################
# FAILURE LOG
#################################
FAIL_LOG="${SEG_ROOT}/failed_subjects.log"
echo "sub,ses,step,error_message" > "${FAIL_LOG}"

#################################
# SAFE RUN FUNCTION
#################################
safe_run() {
    local SUB="$1"
    local SES="$2"
    local STEP="$3"
    shift 3
    "$@" || {
        echo "${SUB},${SES},${STEP},FAILED" >> "${FAIL_LOG}"
        echo "  WARNING: ${STEP} failed for ${SUB} ${SES}, skipping..."
        return 1
    }
}

#################################
# MAIN LOOP
#################################
for SUB_DIR in "${BIDS_ROOT}"/sub-*; do
    SUB=$(basename "${SUB_DIR}")

    for SES_DIR in "${SUB_DIR}"/ses-*; do
        SES=$(basename "${SES_DIR}")

        echo "Processing ${SUB} ${SES}"

        WORKDIR="${SEG_ROOT}/${SUB}/${SES}"
        mkdir -p "${WORKDIR}"
        cd "${WORKDIR}"

        #################################
        # COPY T1
        #################################
        T1_SRC="${BIDS_ROOT}/${SUB}/${SES}/anat/${SUB}_${SES}_T1w.nii.gz"
        [[ -f "${T1_SRC}" ]] || { 
            echo "  Missing T1, skipping"
            echo "${SUB},${SES},COPY_T1,MISSING" >> "${FAIL_LOG}"
            continue
        }
        safe_run "$SUB" "$SES" "COPY_T1" cp "${T1_SRC}" T1.nii.gz || continue

        #################################
        # SYNTHSTRIP (replaces BET)
        #################################
        SYNTHSTRIP_IMG="synthstrip.nii.gz"
        SYNTHSTRIP_MASK="synthstrip_mask.nii.gz"

        if [[ -f "${SYNTHSTRIP_MASK}" ]]; then
            echo "  SynthStrip already done, skipping"
        else
            echo "  Running SynthStrip via Docker"
            safe_run "$SUB" "$SES" "SYNTHSTRIP" docker run --rm \
                -v ~/license.txt:/Applications/freesurfer/6.0.0/license.txt:ro \
                -v "${WORKDIR}":/data \
                freesurfer/freesurfer:7.4.1 \
                mri_synthstrip \
                    -i /data/T1.nii.gz \
                    -o /data/${SYNTHSTRIP_IMG} \
                    -m /data/${SYNTHSTRIP_MASK} || continue
        fi

        #################################
        # FAST 
        #################################
        if [[ -f synthstrip_seg_2.nii.gz ]]; then
            echo "  FAST already done, skipping"
        else
            # FAST expects a brain-extracted T1; we use the synthstrip brain
            safe_run "$SUB" "$SES" "FAST" fast -g "${SYNTHSTRIP_IMG}" || continue
        fi

        #################################
        # FIRST (use L_Thal_first.vtk as sentinel)
        #################################
        if [[ -f first-L_Thal_first.vtk ]]; then
            echo "  FIRST already done, skipping"
        else
            safe_run "$SUB" "$SES" "FIRST" run_first_all -i T1.nii.gz -o first || continue
        fi

        #################################
        # B0 + REGISTRATION
        #################################
        DWI_PRE="${DWI_ROOT}/${SUB}/${SES}/dwi_preprocessed.nii"
        [[ -f "${DWI_PRE}" ]] || { 
            echo "  Missing DWI, skipping" 
            echo "${SUB},${SES},DWI,MISSING" >> "${FAIL_LOG}"
            continue
        }

        safe_run "$SUB" "$SES" "FSLROI" fslroi "${DWI_PRE}" B0.nii.gz 0 1 || continue
        safe_run "$SUB" "$SES" "FLIRT_B0" flirt -in B0.nii.gz -ref T1.nii.gz -omat B0_to_T1.mat || continue
        safe_run "$SUB" "$SES" "INV_XFM" convert_xfm -omat T1_to_B0.mat -inverse B0_to_T1.mat || continue
        safe_run "$SUB" "$SES" "GM_FLIRT" flirt -in synthstrip_seg_1.nii.gz -ref B0.nii.gz -applyxfm -init T1_to_B0.mat -interp nearestneighbour -out GM_B0.nii.gz || continue
        safe_run "$SUB" "$SES" "GM_FLIRT" flirt -in synthstrip_seg_2.nii.gz -ref B0.nii.gz -applyxfm -init T1_to_B0.mat -interp nearestneighbour -out WM_B0.nii.gz || continue
        safe_run "$SUB" "$SES" "GM_FLIRT" fslmaths GM_B0.nii.gz -add WM_B0.nii.gz mask_B0.nii.gz || continue

        #################################
        # ROI LOOP
        #################################
        for ROI_PAIR in "${ROIS[@]}"; do
            ROI="${ROI_PAIR%%:*}"
            LABEL="${ROI_PAIR##*:}"

            if [[ -f "${ROI}_B0_masked.nii.gz" ]]; then
                echo "  ROI ${ROI} already processed, skipping"
                continue
            fi

            safe_run "$SUB" "$SES" "MESH_TO_VOL_${ROI}" first_utils --meshToVol -i "${SYNTHSTRIP_IMG}" -m "first-${ROI}_first.vtk" -r "${SYNTHSTRIP_IMG}" -l "${LABEL}" -o "${ROI}.nii.gz" || continue
            safe_run "$SUB" "$SES" "BIN_${ROI}" fslmaths "${ROI}.nii.gz" -bin "${ROI}.nii.gz" || continue
            safe_run "$SUB" "$SES" "FLIRT_ROI_${ROI}" flirt -in "${ROI}.nii.gz" -ref B0.nii.gz -applyxfm -init T1_to_B0.mat -interp nearestneighbour -out "${ROI}_B0.nii.gz" || continue
            safe_run "$SUB" "$SES" "MASK_ROI_${ROI}" fslmaths "${ROI}_B0.nii.gz" -mul mask_B0.nii.gz "${ROI}_B0_masked.nii.gz" || continue

            # VOXEL STATS
            read VOX VOL <<< $(fslstats "${ROI}_B0_masked.nii.gz" -V) || { echo "${SUB},${SES},VOXEL_STATS_${ROI},FAILED" >> "${FAIL_LOG}"; continue; }
            echo "${SUB},${SES},${ROI},${VOX},${VOL}" >> "${VOXELS_CSV}"

            # METRIC LOOP
            for METRIC in "${METRICS[@]}"; do
                METRIC_IMG="${DWI_ROOT}/${SUB}/${SES}/metrics/${METRIC}.nii"
                [[ -f "${METRIC_IMG}" ]] || continue
                MEAN=$(fslmeants -i "${METRIC_IMG}" -m "${ROI}_B0_masked.nii.gz") || { echo "${SUB},${SES},METRIC_${METRIC}_${ROI},FAILED" >> "${FAIL_LOG}"; continue; }
                echo "${SUB},${SES},${METRIC},${ROI},${MEAN}" >> "${MEANS_CSV}"
            done
        done
    done
done


echo "======================================"
echo "Finished."
echo "Means  CSV : ${MEANS_CSV}"
echo "Voxels CSV : ${VOXELS_CSV}"
echo "Failures   : ${FAIL_LOG}"
echo "======================================"
