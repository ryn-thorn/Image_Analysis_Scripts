#!/bin/bash

# ==========================
# Script for PET registration and ROI extraction
# bash pet_registration.sh --fbb /data/FBB --fbp /data/FBP --outcsv /data/roi_results.csv

# ==========================

while [[ $# -gt 0 ]]; do
    case $1 in
        --fbb)
            FBB_DIR="$2"
            shift 2
            ;;
        --fbp)
            FBP_DIR="$2"
            shift 2
            ;;
        --outcsv)
            CSV_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option $1"
            exit 1
            ;;
    esac
done

# Default CSV if not provided
CSV_FILE=${CSV_FILE:-"roi_means.csv"}
echo "subjID,file,ctx,WhlCbl" > "$CSV_FILE"


# --- FSL template ---
MNI_TEMPLATE="/usr/local/fsl/data/standard/MNI152_T1_1mm.nii.gz"

# --- ROIs ---
ROI_CTX="voi_ctx_1mm.nii"
ROI_CBL="voi_WhlCbl_1mm.nii"

# --- Output CSV ---
CSV_FILE="roi_means.csv"
echo "subjID,file,ctx,WhlCbl" > $CSV_FILE

# --- Function to process a folder ---
process_folder() {
    local INPUT_DIR=$1
    shift
    local FILE_PATTERNS=("$@")  # list of filenames to look for

    echo "Processing $INPUT_DIR ..."

    # Temporary folder for intermediate files
    TMP_DIR="${INPUT_DIR}/tmp_MNI"
    mkdir -p $TMP_DIR

    # Step 1: Linear registration to MNI and merge
    LINEAR_MERGE_LIST=()
    for subj in "$INPUT_DIR"/*; do
        if [[ -d "$subj" ]]; then
            subjID=$(basename "$subj")
            for fname in "${FILE_PATTERNS[@]}"; do
                infile="$subj/$fname"
                if [[ -f "$infile" ]]; then
                    outlin="${TMP_DIR}/${subjID}_${fname%.nii.gz}_lin2MNI.nii.gz"
                    echo "Flirt linear registration: $infile -> $outlin"
                    flirt -in "$infile" -ref "$MNI_TEMPLATE" -out "$outlin" -omat "${outlin%.nii.gz}.mat"
                    LINEAR_MERGE_LIST+=("$outlin")
                fi
            done
        fi
    done

    # Merge and compute average
    MERGED="${TMP_DIR}/merged_lin.nii.gz"
    fslmerge -t "$MERGED" "${LINEAR_MERGE_LIST[@]}"
    AVG="${TMP_DIR}/avg_lin.nii.gz"
    fslmaths "$MERGED" -Tmean "$AVG"
    echo "Average PET computed: $AVG"

    # Step 2: Affine + nonlinear registration to average map
    for subj in "$INPUT_DIR"/*; do
        if [[ -d "$subj" ]]; then
            subjID=$(basename "$subj")
            for fname in "${FILE_PATTERNS[@]}"; do
                infile="$subj/$fname"
                if [[ -f "$infile" ]]; then
                    # Linear registration to average
                    outlin="${TMP_DIR}/${subjID}_${fname%.nii.gz}_lin2AVG.nii.gz"
                    flirt -in "$infile" -ref "$AVG" -out "$outlin" -omat "${outlin%.nii.gz}.mat"

                    # Nonlinear registration using previous affine
                    outnonlin="${subj}/${fname%.nii.gz}_MNI.nii.gz"
                    fnirt --in="$infile" --aff="${outlin%.nii.gz}.mat" --ref="$AVG" --iout="$outnonlin"
                fi
            done
        fi
    done

    # Step 3: Extract ROI mean values
    for subj in "$INPUT_DIR"/*; do
        if [[ -d "$subj" ]]; then
            subjID=$(basename "$subj")
            for fname in "${FILE_PATTERNS[@]}"; do
                regfile="${subj}/${fname%.nii.gz}_MNI.nii.gz"
                if [[ -f "$regfile" ]]; then
                    mean_ctx=$(fslmeants -i "$regfile" -m "$ROI_CTX")
                    mean_cbl=$(fslmeants -i "$regfile" -m "$ROI_CBL")
                    echo "${subjID},${fname%.nii.gz}_MNI.nii.gz,${mean_ctx},${mean_cbl}" >> $CSV_FILE
                fi
            done
        fi
    done

    # Clean up
    rm -rf "$TMP_DIR"
}

# --- Process both folders ---
process_folder "$FBB_DIR" "PET_FBB.nii.gz" "PET_PiB.nii.gz"
process_folder "$FBP_DIR" "florbetapir.nii.gz" "PiB.nii.gz"

echo "Processing complete. ROI means saved to $CSV_FILE"
