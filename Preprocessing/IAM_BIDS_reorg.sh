#!/bin/bash
set -uo pipefail  # NOTE: removed -e to prevent silent exits

##########################################
# IAM DICOM → BIDS-like NIfTI Organizer
# Version: 2.3
# Requirements: dcm2niix, dcmdump
##########################################

SRC_NII_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/03_nii/Y0"
SRC_DICOM_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/02_dicom"
OUT_BASE="/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS"

SESSIONS=("Y0" "Y2" "Y4" "Y6")
MODS=("anat" "dwi" "fmri" "vista" "other")

declare -A SUFFIX_MAP
SUFFIX_MAP=( ["Y2"]="b" ["Y4"]="c" ["Y6"]="d" )

DEBUG_LOG="$OUT_BASE/debug_full.log"
mkdir -p "$OUT_BASE"
echo "=== IAM BIDS Conversion Log ===" > "$DEBUG_LOG"
date >> "$DEBUG_LOG"

# Step 1: Create folder structure
echo "📁 Creating folder structure ..." | tee -a "$DEBUG_LOG"
for subj_dir in "$SRC_NII_BASE"/*; do
    [[ -d "$subj_dir" ]] || continue
    subj_id=$(basename "$subj_dir")
    num=${subj_id#IAM_}
    bids_subj="sub-$num"
    subj_out="$OUT_BASE/$bids_subj"

#     for ses in "${SESSIONS[@]}"; do
#         for mod in "${MODS[@]}"; do
#             mkdir -p "$subj_out/ses-$ses/$mod"
#         done
#     done
done
echo "✅ Folder structure created." | tee -a "$DEBUG_LOG"

# Step 2: Conversion + metadata extraction
echo "🔄 Converting and sorting ..." | tee -a "$DEBUG_LOG"

PARTICIPANTS_TSV="$OUT_BASE/participants.tsv"
echo -e "participant_id\tsex\tage_Y0" > "$PARTICIPANTS_TSV"

for ses in "${SESSIONS[@]}"; do
    ses_dir="$SRC_DICOM_BASE/$ses"
    echo "Looking in session folder: $ses_dir" | tee -a "$DEBUG_LOG"
    [[ -d "$ses_dir" ]] || { echo "⚠️ Skipping $ses (no folder)" | tee -a "$DEBUG_LOG"; continue; }

    for subj_folder in "$ses_dir"/*; do
        [[ -d "$subj_folder" ]] || continue
        subj_id=$(basename "$subj_folder")
        num=${subj_id#IAM_}
        bids_subj="sub-$num"
        subj_out="$OUT_BASE/$bids_subj/ses-$ses"
        mkdir -p "$subj_out"

        echo "Processing subject $subj_id → $bids_subj" | tee -a "$DEBUG_LOG"
        log_file="$OUT_BASE/${bids_subj}/${bids_subj}_ses-${ses}.log"
        echo "🧠 Sequence log for $bids_subj ($ses)" > "$log_file"
        echo "----------------------------------------" >> "$log_file"

        # Extract sex/age from Y0 DICOMs safely
        if [[ "$ses" == "Y0" ]]; then
            first_dcm=$(find "$subj_folder" -type f -name '*.dcm' | head -n 1)
            if [[ -f "$first_dcm" ]]; then
                sex=$(dcmdump +P PatientSex "$first_dcm" 2>/dev/null | awk -F'[][]' '{print $2}' || echo "n/a")
                age=$(dcmdump +P PatientAge "$first_dcm" 2>/dev/null | awk -F'[][]' '{print $2}' || echo "n/a")
                [[ -z "$sex" ]] && sex="n/a"
                [[ -z "$age" ]] && age="n/a"
            else
                sex="n/a"
                age="n/a"
                echo "⚠️ No DICOMs found for sex/age extraction" | tee -a "$log_file" "$DEBUG_LOG"
            fi
        else
            sex="n/a"
            age="n/a"
        fi

        # Track which scans exist
        declare -A ALL_HEADERS=()

        # Loop over sequence folders (depth 1)
        for scan_dir in "$subj_folder"/*; do
            [[ -d "$scan_dir" ]] || continue
            # Skip empty folders
            if [[ -z "$(ls -A "$scan_dir")" ]]; then
                echo "  ⚠️ Skipping empty folder $scan_dir" >> "$log_file"
                continue
            fi

            scan_name=$(basename "$scan_dir")
            safe_name=$(echo "$scan_name" | tr ' ' '_' | tr -cd '[:alnum:]_-.')
            nii_out="$subj_out/${bids_subj}_ses-${ses}_${safe_name}.nii.gz"

            echo "  → Converting $scan_name ..." | tee -a "$log_file" "$DEBUG_LOG"

            if ! dcm2niix -z y -f "${bids_subj}_ses-${ses}_${safe_name}" -o "$subj_out" "$scan_dir" >/dev/null 2>&1; then
                echo "    ⚠️ Conversion failed for $scan_name" | tee -a "$log_file" "$DEBUG_LOG"
                continue
            fi

            ALL_HEADERS["${ses}_${safe_name}"]=TRUE
        done

        # Write participant info
        printf "%s\t%s\t%s" "$bids_subj" "$sex" "$age" >> "$PARTICIPANTS_TSV"
        for key in "${!ALL_HEADERS[@]}"; do
            printf "\tTRUE" >> "$PARTICIPANTS_TSV"
        done
        printf "\n" >> "$PARTICIPANTS_TSV"

        echo "✅ Finished $bids_subj $ses" | tee -a "$log_file" "$DEBUG_LOG"
        echo "" >> "$log_file"
    done
done

echo "🎉 Done! Participants summary written to:"
echo "   $PARTICIPANTS_TSV"
echo "Full debug log at: $DEBUG_LOG"
