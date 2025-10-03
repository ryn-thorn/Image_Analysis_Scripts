#!/bin/bash
set -euo pipefail

# ============================================
# Paths (update these for your dataset)
# ============================================
FS_BASE="/Volumes/vdrive/helpern_users/benitez_a/PUMA/PUMA_Imaging/PUMA_BIDS/derivatives/freesurfer_6.0"
OUT_BASE="/Volumes/vdrive/helpern_users/benitez_a/PUMA/PUMA_Imaging/PUMA_BIDS/derivatives/native_subcortical_roi_analysis"
DKI_BASE="/Volumes/vdrive/helpern_users/benitez_a/PUMA/PUMA_Imaging/PUMA_BIDS/derivatives/dki_pydesigner_v1.0"
RAW_BASE="/Volumes/vdrive/helpern_users/benitez_a/PUMA/PUMA_Imaging/PUMA_BIDS"
PY_THRESHOLD="/Volumes/vdrive/helpern_share/Image_Analysis_Scripts/Misc/threshold_nifti.py"  # <-- path to the Python thresholding script

# ============================================
# ROI IDs and Names
# ============================================
ROI_IDS=(10 11 12 13 17 18 24 26 28)
ROI_NAMES=(Left-Thalamus Left-Caudate Left-Putamen Left-Pallidum Left-Hippocampus Left-Amygdala CSF Left-Accumbens Left-VentralDC)

# ============================================
# Logging
# ============================================
LOGFILE="${OUT_BASE}/missing_T1.log"
> "$LOGFILE"

# ============================================
# Output CSV
# ============================================
CSV="${OUT_BASE}/roi_results.csv"
{
  echo -n "SubjID,Metric"
  for name in "${ROI_NAMES[@]}"; do
    echo -n ",${name}"
  done
  echo
} > "$CSV"

# ============================================
# Helper function to find nii or nii.gz
# ============================================
find_nii() {
    file="$1"
    if [[ -f "${file}.gz" ]]; then
        echo "${file}.gz"
    elif [[ -f "$file" ]]; then
        echo "$file"
    else
        echo ""
    fi
}

# ============================================
# Main Loop
# ============================================
echo "Looking in $FS_BASE"

for subj in $(ls "$FS_BASE"); do
    subj_dir="${FS_BASE}/${subj}"
    aseg="${subj_dir}/mri/aparc+aseg.mgz"

    if [[ ! -f "$aseg" ]]; then
        echo "Skipping $subj (no aseg found)"
        continue
    fi

    echo "Processing $subj ..."
    subj_out="${OUT_BASE}/${subj}"
    mkdir -p "$subj_out"

    # Convert aseg to nii
    aseg_nii="${subj_out}/aparc+aseg.nii.gz"
    if [[ ! -f "$aseg_nii" ]]; then
        mri_convert "$aseg" "$aseg_nii"
    fi

    # Extract ROIs
    for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
        id=${ROI_IDS[$i]}
        name=${ROI_NAMES[$i]}
        out="${subj_out}/${name}.nii.gz"
        if [[ ! -f "$out" ]]; then
            fslmaths "$aseg_nii" -thr $id -uthr $id -bin "$out"
        fi
    done

    # ============================================
    # Grab B0 from dwi_preprocessed
    # ============================================
    dki_dir="${DKI_BASE}/${subj}"
    dwi_file=$(find_nii "${dki_dir}/dwi_preprocessed.nii")

    if [[ -n "$dwi_file" ]]; then
        if [[ ! -f "${subj_out}/B0.nii.gz" ]]; then
            echo "Extracting B0 for $subj ..."
            fslmaths "$dwi_file" -Tmean "${subj_out}/B0.nii.gz"
        fi
    else
        echo "No DWI file for $subj"
        continue
    fi

    # ============================================
    # Find raw T1
    # ============================================
    t1_path=$(find_nii "${RAW_BASE}/${subj}/anat/t1_mprage_sag_p2_iso.nii")
    if [[ -f "$t1_path" ]]; then
        cp -n "$t1_path" "${subj_out}/T1.nii"
    else
        echo "Missing T1 for $subj" >> "$LOGFILE"
        continue
    fi

    # Register T1 to B0
    if [[ ! -f "${subj_out}/T1_to_B0.mat" ]]; then
        flirt -in "${subj_out}/T1.nii" -ref "${subj_out}/B0.nii.gz" -omat "${subj_out}/T1_to_B0.mat" -out "${subj_out}/T1_in_B0.nii.gz"
    fi

    # Apply transform to ROIs
    for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
        name=${ROI_NAMES[$i]}
        in_roi="${subj_out}/${name}.nii.gz"
        out_roi="${subj_out}/${name}_B0.nii.gz"
        if [[ ! -f "$out_roi" ]]; then
            flirt -in "$in_roi" -ref "${subj_out}/B0.nii.gz" -applyxfm -init "${subj_out}/T1_to_B0.mat" -out "$out_roi" -interp nearestneighbour
        fi
    done

    # ============================================
    # Masking step: MD <= 1.5 AND FA <= 0.4 using Python
    # ============================================
    metrics_dir="${dki_dir}/metrics"
    md_file=$(find_nii "${metrics_dir}/dti_md.nii")
    fa_file=$(find_nii "${metrics_dir}/dti_fa.nii")
    combo_mask="${subj_out}/MDFA_mask.nii.gz"

    if [[ -f "$md_file" && -f "$fa_file" ]]; then
        python "$PY_THRESHOLD" "$fa_file" "$md_file" "$combo_mask" 0.4 1.5

        # Apply mask to each ROI
        for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
            name=${ROI_NAMES[$i]}
            roi="${subj_out}/${name}_B0.nii.gz"
            masked_roi="${subj_out}/${name}_B0_masked.nii.gz"
            if [[ -f "$roi" ]]; then
                fslmaths "$roi" -mul "$combo_mask" -bin "$masked_roi"
            fi
        done
    else
        echo "Missing MD or FA metric for $subj — skipping mask step"
    fi

    # ============================================
    # ROI analysis (FA, MD, MK)
    # ============================================
    for metric in dti_fa dti_md dki_mk; do
        metric_file=$(find_nii "${metrics_dir}/${metric}.nii")
        if [[ ! -f "$metric_file" ]]; then
            echo "Missing $metric for $subj"
            continue
        fi

        row="${subj},${metric}"
        for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
            name=${ROI_NAMES[$i]}
            roi="${subj_out}/${name}_B0_masked.nii.gz"
            if [[ -f "$roi" ]]; then
                mean=$(fslmeants -i "$metric_file" -m "$roi" | awk '{sum+=$1} END {if (NR>0) print sum/NR; else print "NA"}')
                row="${row},${mean}"
            else
                row="${row},NA"
            fi
        done

        echo "$row" >> "$CSV"
    done
done

echo "Done! Combined CSV is at $CSV"


