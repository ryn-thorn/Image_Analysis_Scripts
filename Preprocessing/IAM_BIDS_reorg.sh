#!/bin/bash
set -euo pipefail

##########################################
# IAM DICOM → BIDS-like NIfTI Organizer
# Version: 2.0
# Requirements: dcm2niix, dcmdump
##########################################

SRC_NII_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/03_nii/Y0"
SRC_DICOM_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/02_dicom"
OUT_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS"

SESSIONS=("Y0" "Y2" "Y4" "Y6")
MODS=("anat" "dwi" "fmri" "vista" "other")

declare -A SUFFIX_MAP
SUFFIX_MAP=( ["Y2"]="b" ["Y4"]="c" ["Y6"]="d" )

PARTICIPANTS_TSV="$OUT_BASE/participants.tsv"
TMP_PARTICIPANTS="$OUT_BASE/participants_tmp.tsv"
mkdir -p "$OUT_BASE"

echo "participant_id	sex	age_Y0" > "$TMP_PARTICIPANTS"

# Step 1: Create folder structure
echo "📁 Creating folder structure ..."
for subj_dir in "$SRC_NII_BASE"/*; do
    [[ -d "$subj_dir" ]] || continue
    subj_id=$(basename "$subj_dir")  # e.g., IAM_1001
    num=${subj_id#IAM_}
    bids_subj="sub-$num"
    subj_out="$OUT_BASE/$bids_subj"

    for ses in "${SESSIONS[@]}"; do
        for mod in "${MODS[@]}"; do
            mkdir -p "$subj_out/ses-$ses/$mod"
        done
    done
done
echo "✅ Folder structure created."

# Collect global header list (to expand later)
declare -A ALL_HEADERS

# Step 2: Conversion + metadata extraction
echo "🔄 Converting and sorting ..."
for ses in "${SESSIONS[@]}"; do
    ses_dir="$SRC_DICOM_BASE/$ses"
    [[ -d "$ses_dir" ]] || { echo "⚠️ Skipping $ses (no folder)"; continue; }

    for subj_folder in "$ses_dir"/*; do
        [[ -d "$subj_folder" ]] || continue
        subj_name=$(basename "$subj_folder")
        subj_num=$(echo "$subj_name" | sed -E 's/IAM_([0-9]+).*/\1/')
        bids_subj="sub-$subj_num"
        subj_out="$OUT_BASE/$bids_subj/ses-$ses"

        [[ -d "$subj_out" ]] || continue

        # Optional: extract sex/age from Y0 DICOMs
        if [[ "$ses" == "Y0" ]]; then
            first_dcm=$(find "$subj_folder" -type f -name '*.dcm' | head -n 1 || true)
            if [[ -n "$first_dcm" ]]; then
                sex=$(dcmdump +P PatientSex "$first_dcm" 2>/dev/null | awk -F'[' '{print $2}' | awk -F']' '{print $1}')
                age=$(dcmdump +P PatientAge "$first_dcm" 2>/dev/null | awk -F'[' '{print $2}' | awk -F']' '{print $1}' | sed 's/Y//')
            else
                sex="NA"; age="NA"
            fi
            echo -e "${bids_subj}\t${sex}\t${age}" >> "$TMP_PARTICIPANTS"
        fi

        # Scan all sequence folders
        find "$subj_folder" -type d -mindepth 1 -maxdepth 1 | while read -r scan_dir; do
            scan_name=$(basename "$scan_dir")
            out_name="${bids_subj}_${ses}_${scan_name}.nii.gz"

            case "$scan_name" in
                *T1*|*T2*|*MPRAGE*) dest="$subj_out/anat" ;;
                *DKI*|*FBI*) dest="$subj_out/dwi" ;;
                *Task*|*Resting_State*|*rsfMRI*) dest="$subj_out/fmri" ;;
                *ViSTa*|*VISTA*|*vista*) dest="$subj_out/vista" ;;
                *) dest="$subj_out/other" ;;
            esac

            ALL_HEADERS["${ses}_${scan_name}"]=1

            # Skip if already exists
            if [[ -f "$dest/$out_name" ]]; then
                echo "⏭️ Skipping existing $out_name"
                continue
            fi

            echo "🧠 Converting: $scan_name → $out_name"
            if ! dcm2niix -z y -f "$out_name" -o "$dest" "$scan_dir" >/dev/null 2>&1; then
                echo "⚠️ Conversion failed for $scan_dir"
            fi
        done
    done
done

# Step 3: Build participants.tsv with TRUE/FALSE columns
echo "🧾 Building participants.tsv ..."

# Build header
{
    echo -n "participant_id	sex	age_Y0"
    for hdr in "${!ALL_HEADERS[@]}"; do
        echo -ne "\t${hdr}"
    done
    echo
} > "$PARTICIPANTS_TSV"

# Populate TRUE/FALSE for each subject
tail -n +2 "$TMP_PARTICIPANTS" | while IFS=$'\t' read -r pid sex age; do
    echo -n "${pid}\t${sex}\t${age}"
    subj_path="$OUT_BASE/$pid"
    for hdr in "${!ALL_HEADERS[@]}"; do
        ses=${hdr%%_*}
        seq=${hdr#*_}
        f=$(find "$subj_path/ses-$ses" -type f -name "*${seq}.nii.gz" | head -n 1 || true)
        [[ -n "$f" ]] && echo -ne "\tTRUE" || echo -ne "\tFALSE"
    done
    echo
done >> "$PARTICIPANTS_TSV"

rm -f "$TMP_PARTICIPANTS"
echo "🎉 Done! Participants summary written to:"
echo "   $PARTICIPANTS_TSV"
