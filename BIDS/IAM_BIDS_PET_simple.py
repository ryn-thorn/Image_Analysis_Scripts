#!/usr/bin/env bash
set -uo pipefail

DICOM_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/PET"
DST_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS"
SESSION="Y0"

for DICOM_SUB in "${DICOM_BASE}"/IAM_*; do
    [[ -d "$DICOM_SUB" ]] || continue

    subj=$(basename "$DICOM_SUB")
    subj_id="${subj#IAM_}"

    DST_DIR="${DST_BASE}/sub-${subj_id}/ses-${SESSION}/pet"
    mkdir -p "$DST_DIR"

    # Skip subject if output folder already has files
    if [[ $(ls -A "$DST_DIR") ]]; then
        echo "Skipping subject $subj_id, output already exists."
        continue
    fi

    echo "Converting DICOMs for subject $subj_id..."
    # Convert DICOMs to NIfTI
    dcm2niix -b y -f "%f_%s_%p_%d" -z y -o "$DST_DIR" "$DICOM_SUB"

    # Rename resulting files according to previous convention
    for f in "$DST_DIR"/*; do
        [[ -f "$f" ]] || continue
        fname=$(basename "$f")

        # Remove IAM_<sub>_<series>_ or sub-<sub>_ prefix if present
        rest="${fname#IAM_${subj_id}_}"
        rest="${rest#sub-${subj_id}_}"
        rest="${rest#*_}"

        # Remove MUSC_ if present
        rest="${rest/MUSC_/}"

        # Base output name
        if [[ "$fname" == *Dose_Report* ]]; then
            if [[ "$fname" == *.nii.gz ]]; then
                base="sub-Brain_Dose_Report.nii.gz"
            else
                base="sub-Brain_Dose_Report.json"
            fi
        else
            base="sub-${subj_id}_ses-${SESSION}_${rest}"
        fi

        out="${DST_DIR}/${base}"

        # Append _a, _b etc. if duplicate
        if [[ -e "$out" ]]; then
            if [[ "$out" == *.nii.gz ]]; then
                stem="${out%.nii.gz}"
                ext=".nii.gz"
            else
                stem="${out%.*}"
                ext=".${out##*.}"
            fi
            suffix=a
            while [[ -e "${stem}_${suffix}${ext}" ]]; do
                suffix=$(printf "%b" "$(printf '\\%03o' $(( $(printf '%d' "'$suffix") + 1 )) )")
            done
            out="${stem}_${suffix}${ext}"
        fi

        mv -- "$f" "$out"
    done
done
