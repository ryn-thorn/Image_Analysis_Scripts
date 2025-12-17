#!/usr/bin/env bash
set -euo pipefail

SRC_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/PET/nii_wave2"
DST_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS"
SESSION="Y0"

for SRC_DIR in "${SRC_BASE}"/IAM_*; do
    [[ -d "$SRC_DIR" ]] || continue

    subj=$(basename "$SRC_DIR")
    subj_id="${subj#IAM_}"

    DST_DIR="${DST_BASE}/sub-${subj_id}/ses-${SESSION}/pet"
    mkdir -p "$DST_DIR"

    for f in "$SRC_DIR"/*; do
        fname=$(basename "$f")

        # Remove IAM_<sub>_<series>_
        rest="${fname#IAM_${subj_id}_}"
        rest="${rest#*_}"

        # Remove MUSC_
        rest="${rest/MUSC_/}"

        # Base output name
        if [[ "$fname" == *Dose_Report* ]]; then
            if [[ "$fname" == *.nii.gz ]]; then
                base="IAM_Brain_Dose_Report.nii.gz"
            else
                base="IAM_Brain_Dose_Report.json"
            fi
        else
            base="sub-${subj_id}_ses-${SESSION}_${rest}"
        fi

        out="${DST_DIR}/${base}"

        # If name exists, append _a, _b, _c...
        if [[ -e "$out" ]]; then
            ext=""
            stem="$out"

            # Handle .nii.gz explicitly
            if [[ "$out" == *.nii.gz ]]; then
                ext=".nii.gz"
                stem="${out%.nii.gz}"
            else
                ext=".${out##*.}"
                stem="${out%.*}"
            fi

            suffix=a
            while [[ -e "${stem}_${suffix}${ext}" ]]; do
                suffix=$(printf "%b" "$(printf '\\%03o' $(( $(printf '%d' "'$suffix") + 1 )) )")
            done

            out="${stem}_${suffix}${ext}"
        fi

        cp "$f" "$out"
    done
done
