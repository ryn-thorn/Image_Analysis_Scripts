#!/bin/bash

set -euo pipefail
shopt -s nullglob

# -----------------------------
# Force FIRST to run locally
# -----------------------------
export FSLPARALLEL=0
unset SGE_ROOT SGE_CELL SGE_QMASTER_PORT SGE_EXECD_PORT

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

ROI_MEANS_FILE="$OUT_FOLDER/roi_means.csv"
ROI_VOXELS_FILE="$OUT_FOLDER/roi_voxel_vals.csv"

> "$ROI_MEANS_FILE"
> "$ROI_VOXELS_FILE"

METRICS=("dki_mk" "dti_fa" "dti_md")
HEADERS_CREATED=false

# -----------------------------
# Loop over subjects/sessions
# -----------------------------
for sub_dir in "$BIDS_FOLDER"/sub-*; do
    [[ -d "$sub_dir" ]] || continue
    sub=$(basename "$sub_dir")

    for ses_dir in "$sub_dir"/ses-*; do
        [[ -d "$ses_dir" ]] || continue
        ses=$(basename "$ses_dir")

        echo "=============================="
        echo "Processing $sub $ses"
        echo "=============================="

        OUT_SUB="$OUT_FOLDER/$sub/$ses"
        mkdir -p "$OUT_SUB/intermediate"

        # -----------------------------
        # T1 + BET
        # -----------------------------
        T1_IN=$(find "$ses_dir"/anat -name "*_T1w.nii*" | head -n1)
        if [[ ! -f "$T1_IN" ]]; then
            echo "Warning: No T1 found, skipping $sub $ses"
            continue
        fi

        cp "$T1_IN" "$OUT_SUB/T1.nii"

        if [ ! -f "$OUT_SUB/T1_bet.nii" ]; then
            echo "Running BET for $sub $ses"
            bet "$OUT_SUB/T1.nii" "$OUT_SUB/T1_bet_temp.nii" -f 0.4
            bet "$OUT_SUB/T1_bet_temp.nii" "$OUT_SUB/T1_bet.nii" -f 0.4 -g -0.5
            rm -f "$OUT_SUB/T1_bet_temp.nii"
        else
            echo "Skipping BET (already exists)"
        fi

        # -----------------------------
        # FAST
        # -----------------------------
        if [ ! -f "$OUT_SUB/CSF.nii" ] || [ ! -f "$OUT_SUB/WM.nii" ] || [ ! -f "$OUT_SUB/GM.nii" ]; then
            echo "Running FAST for $sub $ses"
            fast -g "$OUT_SUB/T1_bet.nii"

            mv "$OUT_SUB/T1_bet_seg_0.nii.gz" "$OUT_SUB/CSF.nii"
            mv "$OUT_SUB/T1_bet_seg_1.nii.gz" "$OUT_SUB/WM.nii"
            mv "$OUT_SUB/T1_bet_seg_2.nii.gz" "$OUT_SUB/GM.nii"

            mv -f "$OUT_SUB"/T1_bet_* "$OUT_SUB/intermediate/" 2>/dev/null || true
        else
            echo "Skipping FAST (CSF/WM/GM already exist)"
        fi

        # -----------------------------
        # FIRST (T1 space)
        # -----------------------------
        if [ ! -f "$OUT_SUB/first-merged_first.bvars" ]; then
            echo "Running FIRST for $sub $ses"
            run_first_all -i "$OUT_SUB/T1_bet.nii" -o "$OUT_SUB/first"
        else
            echo "Skipping FIRST (bvars/vtk already exist)"
        fi

        # -----------------------------
        # Convert FIRST meshes → volumes
        # -----------------------------
        for vtk in "$OUT_SUB"/first-*_first.vtk; do
            base=$(basename "$vtk" _first.vtk)
            struct=${base#first-}
            OUT_MESH="$OUT_SUB/${base}_corr.nii.gz"

            # Skip if already done
            if [ -f "$OUT_MESH" ]; then
                echo "Skipping meshToVol for $struct (already exists)"
                continue
            fi

            case "$struct" in
                L_Thal) label=10 ;;
                L_Caud) label=11 ;;
                L_Puta) label=12 ;;
                L_Pall) label=13 ;;
                BrStem) label=16 ;;
                L_Hipp) label=17 ;;
                L_Amyg) label=18 ;;
                L_Accu) label=26 ;;
                R_Thal) label=49 ;;
                R_Caud) label=50 ;;
                R_Puta) label=51 ;;
                R_Pall) label=52 ;;
                R_Hipp) label=53 ;;
                R_Amyg) label=54 ;;
                R_Accu) label=58 ;;
                *)
                    echo "Skipping unknown FIRST structure: $struct"
                    continue
                    ;;
            esac

            first_utils --meshToVol \
                -i "$OUT_SUB/T1_bet.nii" \
                -m "$vtk" \
                -r "$OUT_SUB/T1_bet.nii" \
                -l "$label" \
                -o "$OUT_MESH"

            # Binarize ROI
            fslmaths "$OUT_MESH" -bin "$OUT_MESH"
        done

        # -----------------------------
        # Populate ROI_NAMES from existing masked_B0.nii files
        # -----------------------------
        ROI_NAMES=()
        for f in "$OUT_SUB"/*_masked_B0.nii; do
            [ -f "$f" ] || continue
            ROI_NAMES+=("$(basename "$f" _masked_B0.nii)")
        done

        # -----------------------------
        # Diffusion / B0
        # -----------------------------
        DWI_DIR="$PYDESIGNER_FOLDER/$sub/$ses"
        DWI_PRE="$DWI_DIR/dwi_preprocessed.nii"

        if [[ ! -f "$DWI_PRE" ]]; then
            echo "Warning: No dwi_preprocessed.nii, skipping $sub $ses"
        else
            cp "$DWI_PRE" "$OUT_SUB/dwi_preprocessed.nii"
            fslroi "$OUT_SUB/dwi_preprocessed.nii" "$OUT_SUB/B0.nii" 0 1

            flirt -in "$OUT_SUB/B0.nii" \
                  -ref "$OUT_SUB/T1.nii" \
                  -omat "$OUT_SUB/B0_to_T1.mat" \
                  -out "$OUT_SUB/B0_in_T1.nii"

            convert_xfm -omat "$OUT_SUB/T1_to_B0.mat" \
                        -inverse "$OUT_SUB/B0_to_T1.mat"

            # -----------------------------
            # Move ROIs to B0
            # -----------------------------
            corr_rois=("$OUT_SUB"/*_corr.nii.gz)
            for roi in "${corr_rois[@]}"; do
                B0_ROI="${roi%.nii.gz}_B0.nii.gz"
                if [ ! -f "$B0_ROI" ]; then
                    flirt -in "$roi" \
                          -ref "$OUT_SUB/B0.nii" \
                          -applyxfm -init "$OUT_SUB/T1_to_B0.mat" \
                          -interp nearestneighbour \
                          -out "$B0_ROI"
                fi
            done

            for tissue in CSF WM; do
                B0_TISSUE="$OUT_SUB/${tissue}_B0.nii"
                if [ ! -f "$B0_TISSUE" ]; then
                    flirt -in "$OUT_SUB/${tissue}.nii" \
                          -ref "$OUT_SUB/B0.nii" \
                          -applyxfm -init "$OUT_SUB/T1_to_B0.mat" \
                          -interp nearestneighbour \
                          -out "$B0_TISSUE"
                fi
            done

            # -----------------------------
            # Mask ROIs
            # -----------------------------
            for roi in "$OUT_SUB"/*_corr_B0.nii.gz; do
                base=$(basename "$roi" _corr_B0.nii.gz)
                OUT_MASKED="$OUT_SUB/${base}_masked_B0.nii"
                if [ ! -f "$OUT_MASKED" ]; then
                    fslmaths "$roi" \
                        -mas "$OUT_SUB/CSF_B0.nii" -binv \
                        -mas "$OUT_SUB/WM_B0.nii" -binv \
                        "$OUT_MASKED"
                fi
            done
        fi

        # -----------------------------
        # CSV headers
        # -----------------------------
        if [ "$HEADERS_CREATED" = false ] && [ ${#ROI_NAMES[@]} -gt 0 ]; then
            echo "Sub,ses,metric,${ROI_NAMES[*]}" | tr ' ' ',' >> "$ROI_MEANS_FILE"
            echo "Sub,ses,${ROI_NAMES[*]}" | tr ' ' ',' >> "$ROI_VOXELS_FILE"
            HEADERS_CREATED=true
        fi

        # -----------------------------
        # Metric extraction
        # -----------------------------
        if [ ${#ROI_NAMES[@]} -gt 0 ] && [ -f "$DWI_DIR/metrics/${METRICS[0]}.nii" ]; then
            METRICS_DIR="$DWI_DIR/metrics"

            for metric in "${METRICS[@]}"; do
                line="$sub,$ses,$metric"
                for roi in "${ROI_NAMES[@]}"; do
                    val=$(fslmeants -i "$METRICS_DIR/${metric}.nii" \
                                    -m "$OUT_SUB/${roi}_masked_B0.nii" 2>/dev/null || echo "")
                    line+=",$val"
                done
                echo "$line" >> "$ROI_MEANS_FILE"
            done

            line="$sub,$ses"
            for roi in "${ROI_NAMES[@]}"; do
                vox=$(fslstats "$OUT_SUB/${roi}_masked_B0.nii" -V | awk '{print $1}')
                line+=",$vox"
            done
            echo "$line" >> "$ROI_VOXELS_FILE"
        fi

    done
done

echo "================================="
echo "Processing complete."
echo "Outputs saved to $OUT_FOLDER"
echo "================================="
