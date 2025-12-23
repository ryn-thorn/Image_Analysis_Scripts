#!/bin/bash

# ==========================
# PET registration + ROI extraction with progress & resume support
# ==========================

set -euo pipefail

timestamp() {
    date "+[%Y-%m-%d %H:%M:%S]"
}

log() {
    echo "$(timestamp) $1"
}

# --------------------------
# Parse arguments
# --------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --fbb)
            FBB_DIR="$2"; shift 2 ;;
        --fbp)
            FBP_DIR="$2"; shift 2 ;;
        --outcsv)
            CSV_FILE="$2"; shift 2 ;;
        *)
            echo "Unknown option $1"; exit 1 ;;
    esac
done

CSV_FILE=${CSV_FILE:-"roi_means.csv"}

# Initialize CSV only if it doesn't exist
if [[ ! -f "$CSV_FILE" ]]; then
    log "Initializing CSV at $CSV_FILE"
    echo "subjID,file,ctx,WhlCbl" > "$CSV_FILE"
else
    log "Appending to existing CSV: $CSV_FILE"
fi

# --------------------------
# Paths
# --------------------------
MNI_TEMPLATE="/usr/local/fsl/data/standard/MNI152_T1_1mm.nii.gz"
ROI_CTX="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/centiloids_mri-free/Centiloid_Std_VOI/nifti/1mm/voi_ctx_1mm.nii"
ROI_CBL="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/centiloids_mri-free/Centiloid_Std_VOI/nifti/1mm/voi_WhlCbl_1mm.nii"
ROI_CTX_reslice="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/centiloids_mri-free/Centiloid_Std_VOI/nifti/1mm/voi_ctx_1mm_reslice.nii"
ROI_CBL_reslice="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/centiloids_mri-free/Centiloid_Std_VOI/nifti/1mm/voi_WhlCbl_1mm_reslice.nii"

flirt -in $ROI_CTX -ref $MNI_TEMPLATE -out $ROI_CTX_reslice -applyxfm -usesqform -interp nearestneighbour
flirt -in $ROI_CBL -ref $MNI_TEMPLATE -out $ROI_CBL_reslice -applyxfm -usesqform -interp nearestneighbour

# --------------------------
# Folder processor
# --------------------------
process_folder() {
    local INPUT_DIR=$1
    shift
    local FILE_PATTERNS=("$@")

    log "=================================================="
    log "Starting processing of $INPUT_DIR"
    log "Looking for files: ${FILE_PATTERNS[*]}"
    log "=================================================="

    TMP_DIR="${INPUT_DIR}/tmp_MNI"
    mkdir -p "$TMP_DIR"

    # --------------------------
    # Step 1: Linear to MNI
    # --------------------------
    log "Step 1: Linear registration to MNI"

    LINEAR_MERGE_LIST=()
    subj_count=0

    for subj in "$INPUT_DIR"/*; do
        [[ -d "$subj" ]] || continue
        subjID=$(basename "$subj")
        ((subj_count++))

        for fname in "${FILE_PATTERNS[@]}"; do
            infile="$subj/$fname"
            [[ -f "$infile" ]] || continue

            outlin="${TMP_DIR}/${subjID}_${fname%.nii.gz}_lin2MNI.nii.gz"
            mat="${outlin%.nii.gz}.mat"

            if [[ -f "$outlin" ]]; then
                log "[SKIP] FLIRT already done: $outlin"
            else
                log "[FLIRT] ($subjID) $fname → MNI"
                flirt -in "$infile" -ref "$MNI_TEMPLATE" -out "$outlin" -omat "$mat"
            fi

            LINEAR_MERGE_LIST+=("$outlin")
        done
    done

    if [[ ${#LINEAR_MERGE_LIST[@]} -eq 0 ]]; then
        log "[ERROR] No linear-registered files found. Aborting."
        exit 1
    fi

    # --------------------------
    # Step 1b: Merge + mean
    # --------------------------
    MERGED="${TMP_DIR}/merged_lin.nii.gz"
    AVG="${TMP_DIR}/avg_lin.nii.gz"

    if [[ ! -f "$AVG" ]]; then
        log "Merging ${#LINEAR_MERGE_LIST[@]} images"
        fslmerge -t "$MERGED" "${LINEAR_MERGE_LIST[@]}"
        log "Computing group average"
        fslmaths "$MERGED" -Tmean "$AVG"
    else
        log "[SKIP] Average PET already exists"
    fi

    # --------------------------
    # Step 2: Affine + FNIRT
    # --------------------------
    log "Step 2: Affine + nonlinear registration to group average"

    for subj in "$INPUT_DIR"/*; do
        [[ -d "$subj" ]] || continue
        subjID=$(basename "$subj")

        for fname in "${FILE_PATTERNS[@]}"; do
            infile="$subj/$fname"
            [[ -f "$infile" ]] || continue

            final="${subj}/${fname%.nii.gz}_MNI.nii.gz"
            aff="${TMP_DIR}/${subjID}_${fname%.nii.gz}_lin2AVG.mat"
            tmpout="${TMP_DIR}/${subjID}_${fname%.nii.gz}_lin2AVG.nii.gz"

            if [[ -f "$final" ]]; then
                log "[SKIP] FNIRT already done: $final"
                continue
            fi

            log "[FLIRT→AVG] ($subjID) $fname"
            flirt -in "$infile" -ref "$AVG" -omat "$aff" -out "$tmpout"

            log "[FNIRT] ($subjID) $fname (this can take a while)"
            fnirt \
              --in="$infile" \
              --ref="$AVG" \
              --aff="$aff" \
              --iout="$final"
        done
    done

    # --------------------------
    # Step 3: ROI extraction
    # --------------------------
    log "Step 3: ROI mean extraction"

    for subj in "$INPUT_DIR"/*; do
        [[ -d "$subj" ]] || continue
        subjID=$(basename "$subj")

        for fname in "${FILE_PATTERNS[@]}"; do
            regfile="${subj}/${fname%.nii.gz}_MNI.nii.gz"
            [[ -f "$regfile" ]] || continue

            # Avoid duplicate CSV rows
            if grep -q "^${subjID},${fname%.nii.gz}_MNI.nii.gz" "$CSV_FILE"; then
                log "[SKIP] ROI already extracted: $subjID $fname"
                continue
            fi

            log "[ROI] ($subjID) $fname"
            mean_ctx=$(fslmeants -i "$regfile" -m "$ROI_CTX_reslice")
            mean_cbl=$(fslmeants -i "$regfile" -m "$ROI_CBL_reslice")

            echo "${subjID},${fname%.nii.gz}_MNI.nii.gz,${mean_ctx},${mean_cbl}" >> "$CSV_FILE"
        done
    done

    log "Completed processing of $INPUT_DIR"
}

# --------------------------
# Run
# --------------------------
process_folder "$FBB_DIR" "PET_FBB.nii.gz" "PET_PiB.nii.gz"
process_folder "$FBP_DIR" "florbetapir.nii.gz" "PiB.nii.gz"

log "ALL PROCESSING COMPLETE"
log "Final CSV: $CSV_FILE"
