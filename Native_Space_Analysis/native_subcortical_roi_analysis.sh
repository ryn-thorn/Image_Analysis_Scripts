#!/bin/bash
set -euo pipefail

# Base directories
FS_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/freesurfer/freesurfer_6.0/03_Analysis"
OUT_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/freesurfer/native_subcortical_roi_analysis"

# ROI IDs and names (parallel arrays)
ROI_IDS=(10 11 12 13 17 18 24 26 28)
ROI_NAMES=(Left-Thalamus Left-Caudate Left-Putamen Left-Pallidum Left-Hippocampus Left-Amygdala CSF Left-Accumbens Left-VentralDC)

# Log file
LOGFILE="${OUT_BASE}/missing_T1.log"
> "$LOGFILE"

echo "Looking in $FS_BASE"

# Loop through subjects
for subj in $(ls "$FS_BASE"); do
    subj_dir="${FS_BASE}/${subj}"
    aseg="${subj_dir}/mri/aparc+aseg.mgz"

    # Skip junk dirs
    if [[ ! -f "$aseg" ]]; then
        echo "Skipping $subj (no aseg found)"
        continue
    fi

    echo "Processing $subj ..."

    # Make subject output folder
    subj_out="${OUT_BASE}/${subj}"
    mkdir -p "$subj_out"

    # Convert aseg to nii
    aseg_nii="${subj_out}/aparc+aseg.nii.gz"
    mri_convert "$aseg" "$aseg_nii"

    # Extract ROIs
    for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
        id=${ROI_IDS[$i]}
        name=${ROI_NAMES[$i]}
        out="${subj_out}/${name}.nii.gz"
        fslmaths "$aseg_nii" -thr $id -uthr $id -bin "$out"
    done

    # Grab B0
    dki_dir="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pydesigner/dki_pydesigner/02_Data/${subj}"
    dki_file="${dki_dir}/dwi_preprocessed.nii.gz"
    if [[ -f "$dki_file" ]]; then
        fslsplit "$dki_file" "${subj_out}/vol"
        mv "${subj_out}/vol0000.nii.gz" "${subj_out}/B0.nii.gz"
        rm "${subj_out}"/vol*.nii.gz
    else
        echo "No DKI file for $subj"
    fi

    # Find raw T1 based on suffix
    case "$subj" in
        *b) prefix="Y2";;
        *c) prefix="Y4";;
        *d) prefix="Y6";;
        *) prefix="Y0";;
    esac
    t1_path="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/03_nii/${prefix}/${subj}/anat/t1_mprage_sag_p2_iso.nii"
    if [[ -f "$t1_path" ]]; then
        cp "$t1_path" "${subj_out}/T1.nii"
    else
        echo "Missing T1 for $subj" >> "$LOGFILE"
        continue
    fi

    # Register T1 to B0
    flirt -in "${subj_out}/T1.nii" -ref "${subj_out}/B0.nii.gz" -omat "${subj_out}/T1_to_B0.mat" -out "${subj_out}/T1_in_B0.nii.gz"

    # Apply to ROIs
    for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
        name=${ROI_NAMES[$i]}
        in_roi="${subj_out}/${name}.nii.gz"
        out_roi="${subj_out}/${name}_B0.nii.gz"
        flirt -in "$in_roi" -ref "${subj_out}/B0.nii.gz" -applyxfm -init "${subj_out}/T1_to_B0.mat" -out "$out_roi" -interp nearestneighbour
    done

    # ROI analysis (FA/MD/MK)
    metrics_dir="${dki_dir}/metrics"
    for metric in dti_fa dti_md dti_mk; do
        metric_file="${metrics_dir}/${metric}.nii.gz"
        if [[ ! -f "$metric_file" ]]; then
            echo "Missing $metric for $subj"
            continue
        fi
        for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
            name=${ROI_NAMES[$i]}
            roi="${subj_out}/${name}_B0.nii.gz"
            if [[ -f "$roi" ]]; then
                mean=$(fslmeants -i "$metric_file" -m "$roi" | awk '{sum+=$1} END {if (NR>0) print sum/NR; else print "NA"}')
                echo "$subj,$metric,$name,$mean" >> "${OUT_BASE}/roi_results_long.csv"
            fi
        done
    done
done

echo "Done! Combined CSV is at ${OUT_BASE}/roi_results_long.csv"
