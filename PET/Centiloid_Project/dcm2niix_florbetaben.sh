#!/bin/bash

# Base directories
DICOM_BASE="/Users/kayti/Desktop/Projects/IAM/Centiloids/Calibration/Florbetaben/dicoms"
OUT_BASE="/Users/kayti/Desktop/Projects/IAM/Centiloids/Calibration/Florbetaben/nifti"

# Make sure output base exists
mkdir -p "$OUT_BASE"

# Loop over each project folder (e.g. FBBproject_E-25_PIB_5070)
for project_dir in "$DICOM_BASE"/FBBproject_*; do
    [ -d "$project_dir" ] || continue

    project_name=$(basename "$project_dir")
    echo "🔹 Processing project folder: $project_name"

    # Extract the group (e.g., E-25 or YC-10)
    group=$(echo "$project_name" | grep -oE '(E|YC)-[0-9]+')

    # Loop through subfolders (actual subject DICOM directories)
    for subj_dir in "$project_dir"/*; do
        [ -d "$subj_dir" ] || continue
        subj_folder=$(basename "$subj_dir")

        # Extract subject ID from subfolder name (e.g., Y1001 from Y1001_PET_PiB)
        subj_id=$(echo "$subj_folder" | cut -d'_' -f1)

        # Identify modality from folder name
        if [[ "$subj_folder" == *"MR"* ]]; then
            modality="MR"
            out_name="MR"
        elif [[ "$subj_folder" == *"FBB"* ]]; then
            modality="PET_FBB"
            out_name="PET_FBB"
        elif [[ "$subj_folder" == *"PiB"* || "$subj_folder" == *"PIB"* ]]; then
            modality="PET_PIB"
            out_name="PET_PIB"
        else
            echo "⚠️ Unknown modality in $subj_folder — skipping"
            continue
        fi

        # Output directory
        out_dir="$OUT_BASE/$group/$subj_id"
        mkdir -p "$out_dir"

        echo "   → Converting $subj_id ($modality)"
        dcm2niix -z y -f "$out_name" -o "$out_dir" "$subj_dir"
    done
done

echo "✅ All DICOMs successfully converted to NIfTI!"
