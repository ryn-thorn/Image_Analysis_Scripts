#!/bin/bash

# Base directories
DICOM_BASE="/Users/kayti/Desktop/Projects/IAM/Centiloids/Calibration/Florbetapir/dicoms"
NIFTI_BASE="/Users/kayti/Desktop/Projects/IAM/Centiloids/Calibration/Florbetapir/nifti"

# Loop through all dataset/modality folders
for dataset_modality_dir in "$DICOM_BASE"/*; do
    [ -d "$dataset_modality_dir" ] || continue
    dataset_modality=$(basename "$dataset_modality_dir")

    # Extract dataset (Elder_subject / Young_Control)
    dataset_name=$(echo "$dataset_modality" | sed -E 's/_(MRI|florbetapir|PiB)$//')

    # Extract modality suffix (MRI, florbetapir, PiB)
    modality_suffix=$(echo "$dataset_modality" | grep -oE '(MRI|florbetapir|PiB)$')

    echo "🔹 Processing $dataset_name — modality: $modality_suffix"

    # Loop through subjects
    for subj_dir in "$dataset_modality_dir"/*; do
        [ -d "$subj_dir" ] || continue
        subj_basename=$(basename "$subj_dir")

        # --- Extract clean subject ID ---
        # 1️⃣ Remove known modality tags (_mr, _pib, etc.)
        # 2️⃣ Remove trailing timestamp-style patterns (_7_8_2016_13_20_20)
        subj_id=$(echo "$subj_basename" | sed -E 's/_?(mr|MRI|florbetapir|PiB|pet|pib)//Ig' | sed -E 's/_?[0-9]{1,2}_[0-9]{1,2}_[0-9]{4}_[0-9]{1,2}_[0-9]{1,2}_[0-9]{1,2}$//')

        echo "   → Subject: $subj_id (from $subj_basename)"

        # Flatten .dcm files into top-level subject folder
        find "$subj_dir" -type f -iname "*.dcm" -exec cp {} "$subj_dir/" \;

        # Output directory (merge all modalities per subject)
        out_dir="$NIFTI_BASE/$dataset_name/$subj_id"
        mkdir -p "$out_dir"

        # Convert DICOMs
        dcm2niix -z y -f "$modality_suffix" -o "$out_dir" "$subj_dir"

        # Rename unnamed outputs
        for f in "$out_dir"/*unnamed*; do
            [ -e "$f" ] || continue
            newname=$(echo "$f" | sed "s/unnamed/$modality_suffix/")
            mv "$f" "$newname"
        done
    done
done

echo "✅ All conversions complete, cleaned, and merged!"
