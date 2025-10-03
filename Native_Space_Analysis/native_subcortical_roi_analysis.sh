#!/bin/bash
set -euo pipefail

# ============================================
# Paths
# ============================================
FS_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/freesurfer/freesurfer_6.0/03_Analysis"
OUT_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/freesurfer/native_subcortical_roi_analysis"

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
# Main Loop
# ============================================
echo "Looking in $FS_BASE"

for subj in $(ls "$FS_BASE"); do
    subj_dir="${FS_BASE}/${subj}"
    aseg="${subj_dir}/mri/aparc+aseg.mgz"

    # Skip junk dirs
    if [[ ! -f "$aseg" ]]; then
        echo "Skipping $subj (no aseg found)"
        continue
    fi

    echo "Processing $subj ..."
    subj_out="${OUT_BASE}/${subj}"
    mkdir -p "$subj_out"

    # Convert aseg to nii (skip if exists)
    aseg_nii="${subj_out}/aparc+aseg.nii.gz"
    if [[ ! -f "$aseg_nii" ]]; then
        mri_convert "$aseg" "$aseg_nii"
    fi

    # Extract ROIs (skip if exists)
    for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
        id=${ROI_IDS[$i]}
        name=${ROI_NAMES[$i]}
        out="${subj_out}/${name}.nii.gz"
        if [[ ! -f "$out" ]]; then
            fslmaths "$aseg_nii" -thr $id -uthr $id -bin "$out"
        fi
    done

    # Grab B0
    dki_dir="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pydesigner/dki_pydesigner/02_Data/${subj}"
    dwi_file="${dki_dir}/dwi_preprocessed.nii.gz"
    if [[ -f "$dwi_file" ]]; then
        if [[ ! -f "${subj_out}/B0.nii.gz" ]]; then
            fslsplit "$dwi_file" "${subj_out}/vol"
            mv "${subj_out}/vol0000.nii.gz" "${subj_out}/B0.nii.gz"
            rm "${subj_out}"/vol*.nii.gz
        fi
    else
        echo "No DWI file for $subj"
        continue
    fi

    # Find raw T1
    case "$subj" in
        *b) prefix="Y2";;
        *c) prefix="Y4";;
        *d) prefix="Y6";;
        *) prefix="Y0";;
    esac
    t1_path="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/03_nii/${prefix}/${subj}/anat/t1_mprage_sag_p2_iso.nii"

    if [[ -f "$t1_path" ]]; then
        cp -n "$t1_path" "${subj_out}/T1.nii"  # -n = no overwrite
    else
        echo "Missing T1 for $subj" >> "$LOGFILE"
        continue
    fi

    # Register T1 to B0 (skip if matrix exists)
    if [[ ! -f "${subj_out}/T1_to_B0.mat" ]]; then
        flirt -in "${subj_out}/T1.nii" -ref "${subj_out}/B0.nii.gz" -omat "${subj_out}/T1_to_B0.mat" -out "${subj_out}/T1_in_B0.nii.gz"
    fi

    # Apply transform to ROIs (skip if transformed ROI exists)
    for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
        name=${ROI_NAMES[$i]}
        in_roi="${subj_out}/${name}.nii.gz"
        out_roi="${subj_out}/${name}_B0.nii.gz"
        if [[ ! -f "$out_roi" ]]; then
            flirt -in "$in_roi" -ref "${subj_out}/B0.nii.gz" -applyxfm -init "${subj_out}/T1_to_B0.mat" -out "$out_roi" -interp nearestneighbour
        fi
    done

    # ROI analysis (FA, MD, MK)
    metrics_dir="${dki_dir}/metrics"
    for metric in dti_fa dti_md dki_mk; do
        metric_file="${metrics_dir}/${metric}.nii.gz"
        if [[ ! -f "$metric_file" ]]; then
            echo "Missing $metric for $subj"
            continue
        fi

        row="${subj},${metric}"
        for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
            name=${ROI_NAMES[$i]}
            roi="${subj_out}/${name}_B0.nii.gz"
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
