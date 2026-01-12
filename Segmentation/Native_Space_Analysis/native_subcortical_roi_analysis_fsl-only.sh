#!/bin/bash

# -----------------------------
# Check inputs
# -----------------------------
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <BIDS_FOLDER> <PYDESIGNER_FOLDER> <OUTPUT_FOLDER>"
    exit 1
fi

BIDS_FOLDER=$1
PYDESIGNER_FOLDER=$2
OUT_FOLDER=$3

mkdir -p "$OUT_FOLDER"

# Initialize CSV files (empty for now)
ROI_MEANS_FILE="$OUT_FOLDER/roi_means.csv"
ROI_VOXELS_FILE="$OUT_FOLDER/roi_voxel_vals.csv"

> "$ROI_MEANS_FILE"
> "$ROI_VOXELS_FILE"

METRICS=("dki_mk" "dti_fa" "dti_md")
ROI_NAMES=()
HEADERS_CREATED=false

# -----------------------------
# Loop over subjects and sessions
# -----------------------------
for sub_dir in "$BIDS_FOLDER"/sub-*; do
    [[ -d "$sub_dir" ]] || continue
    sub=$(basename "$sub_dir")
    for ses_dir in "$sub_dir"/ses-*; do
        [[ -d "$ses_dir" ]] || continue
        ses=$(basename "$ses_dir")
        echo "Processing $sub $ses ..."

        OUT_SUB="$OUT_FOLDER/$sub/$ses"
        mkdir -p "$OUT_SUB/intermediate"

        # -----------------------------
        # Copy T1 file and BET
        # -----------------------------
        T1_IN=$(find "$ses_dir"/anat -name "*_T1w.nii*" | head -n1)
        if [[ ! -f "$T1_IN" ]]; then
            echo "Warning: T1 file not found for $sub $ses, skipping BET/FAST"
            continue
        fi
        cp "$T1_IN" "$OUT_SUB/T1.nii"
        echo "Copied T1 file: $T1_IN"

        bet "$OUT_SUB/T1.nii" "$OUT_SUB/T1_bet_temp.nii" -f 0.4
        bet "$OUT_SUB/T1_bet_temp.nii" "$OUT_SUB/T1_bet.nii" -f 0.4 -g -0.5
        [[ -f "$OUT_SUB/T1_bet_temp.nii" ]] && rm "$OUT_SUB/T1_bet_temp.nii"

        # -----------------------------
        # FAST segmentation
        # -----------------------------
        fast -g "$OUT_SUB/T1_bet.nii"
        mv "$OUT_SUB/T1_bet_seg_0.nii.gz" "$OUT_SUB/CSF.nii"
        mv "$OUT_SUB/T1_bet_seg_1.nii.gz" "$OUT_SUB/WM.nii"
        mv "$OUT_SUB/T1_bet_seg_2.nii.gz" "$OUT_SUB/GM.nii"
        for f in "$OUT_SUB"/T1_bet_*; do
            [[ ! "$f" =~ CSF|WM|GM ]] && mv "$f" "$OUT_SUB/intermediate/"
        done

        # -----------------------------
        # FIRST segmentation
        # -----------------------------
        first_output=$(first_all -i "$OUT_SUB/T1_bet.nii" -o "$OUT_SUB/first")
        for f in "$OUT_SUB"/first*; do
            if [[ "$f" =~ _corr.nii.gz ]]; then
                cp "$f" "$OUT_SUB/"
            else
                mv "$f" "$OUT_SUB/intermediate/"
            fi
        done

        # -----------------------------
        # PyDesigner processing
        # -----------------------------
        DWI_DIR="$PYDESIGNER_FOLDER/$sub/$ses"
        DWI_PRE="$DWI_DIR/dwi_preprocessed.nii"
        if [[ ! -f "$DWI_PRE" ]]; then
            echo "Warning: dwi_preprocessed.nii not found for $sub $ses, skipping"
            continue
        fi
        cp "$DWI_PRE" "$OUT_SUB/dwi_preprocessed.nii"

        fslroi "$OUT_SUB/dwi_preprocessed.nii" "$OUT_SUB/B0.nii" 0 1
        flirt -in "$OUT_SUB/B0.nii" -ref "$OUT_SUB/T1.nii" -omat "$OUT_SUB/B0_to_T1.mat" -out "$OUT_SUB/B0_to_T1.nii"

        for roi in "$OUT_SUB"/*_corr.nii.gz; do
            flirt -in "$roi" -ref "$OUT_SUB/T1.nii" -applyxfm -init "$OUT_SUB/B0_to_T1.mat" -out "${roi%.nii.gz}_reg.nii.gz"
        done
        flirt -in "$OUT_SUB/CSF.nii" -ref "$OUT_SUB/T1.nii" -applyxfm -init "$OUT_SUB/B0_to_T1.mat" -out "$OUT_SUB/CSF_reg.nii"
        flirt -in "$OUT_SUB/WM.nii" -ref "$OUT_SUB/T1.nii" -applyxfm -init "$OUT_SUB/B0_to_T1.mat" -out "$OUT_SUB/WM_reg.nii"

        # -----------------------------
        # Masking ROIs (exclude CSF & WM)
        # -----------------------------
        for roi in "$OUT_SUB"/*_corr_reg.nii.gz; do
            fslmaths "$roi" -mas "$OUT_SUB/CSF_reg.nii" -sub "$OUT_SUB/CSF_reg.nii" temp1.nii
            fslmaths temp1.nii -mas "$OUT_SUB/WM_reg.nii" -sub "$OUT_SUB/WM_reg.nii" "${roi%_reg.nii.gz}_masked.nii"
            rm temp1.nii
        done

        # -----------------------------
        # Create CSV headers dynamically after first subject/session
        # -----------------------------
        if [ "$HEADERS_CREATED" = false ]; then
            ROI_NAMES=()
            for f in "$OUT_SUB"/*_masked.nii; do
                [[ -f "$f" ]] || continue
                ROI_NAMES+=("$(basename "$f" _masked.nii)")
            done

            # roi_means header
            header="Sub,ses,metric"
            for roi in "${ROI_NAMES[@]}"; do
                header+=",${roi}"
            done
            echo "$header" >> "$ROI_MEANS_FILE"

            # roi_voxel_vals header
            header_vox="Sub,ses"
            for roi in "${ROI_NAMES[@]}"; do
                header_vox+=",${roi}"
            done
            echo "$header_vox" >> "$ROI_VOXELS_FILE"

            HEADERS_CREATED=true
        fi

        # -----------------------------
        # Extract metrics and voxel counts
        # -----------------------------
        METRICS_DIR="$DWI_DIR/metrics"

        for metric in "${METRICS[@]}"; do
            line="$sub,$ses,$metric"
            for roi in "${ROI_NAMES[@]}"; do
                val=$(fslmeants -i "$METRICS_DIR/${metric}.nii" -m "$OUT_SUB/${roi}_masked.nii" 2>/dev/null)
                line+=",$val"
            done
            echo "$line" >> "$ROI_MEANS_FILE"
        done

        line_vox="$sub,$ses"
        for roi in "${ROI_NAMES[@]}"; do
            vox=$(fslstats "$OUT_SUB/${roi}_masked.nii" -V | awk '{print $1}')
            line_vox+=",$vox"
        done
        echo "$line_vox" >> "$ROI_VOXELS_FILE"

    done
done

echo "Processing complete. Output saved to $OUT_FOLDER."
