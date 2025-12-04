#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <SUBJECTS_DIR>"
    exit 1
fi

SUBJECTS_DIR="$1"
OUTPUT_CSV="$SUBJECTS_DIR/hippocampal_subfields_status.csv"

if [[ ! -d "$SUBJECTS_DIR" ]]; then
    echo "ERROR: SUBJECTS_DIR does not exist"
    exit 1
fi

# Expected regions in hippoSfVolumes-T1.v21.txt
expected_regions=(
"Hippocampal_tail"
"subiculum-body"
"CA1-body"
"subiculum-head"
"hippocampal-fissure"
"presubiculum-head"
"CA1-head"
"presubiculum-body"
"parasubiculum"
"molecular_layer_HP-head"
"molecular_layer_HP-body"
"GC-ML-DG-head"
"CA3-body"
"GC-ML-DG-body"
"CA4-head"
"CA4-body"
"fimbria"
"CA3-head"
"HATA"
"Whole_hippocampal_body"
"Whole_hippocampal_head"
"Whole_hippocampus"
)

check_volumes_complete() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1

    # Must contain all expected region names
    for region in "${expected_regions[@]}"; do
        if ! grep -q "$region" "$file"; then
            return 1
        fi
    done
    return 0
}

echo "subj,ses,lh_complete,rh_complete,cleaned" > "$OUTPUT_CSV"

for subj in "$SUBJECTS_DIR"/sub-*; do
    [[ ! -d "$subj" ]] && continue
    subj_name=$(basename "$subj")

    for ses in "$subj"/ses-*; do
        [[ ! -d "$ses" ]] && continue
        ses_name=$(basename "$ses")

        mri="$ses/mri"

        lh_file="$mri/lh.hippoSfVolumes-T1.v21.txt"
        rh_file="$mri/rh.hippoSfVolumes-T1.v21.txt"

        lh_ok="FALSE"
        rh_ok="FALSE"
        cleaned="FALSE"

        if check_volumes_complete "$lh_file"; then lh_ok="TRUE"; fi
        if check_volumes_complete "$rh_file"; then rh_ok="TRUE"; fi

        # CLEAN ONLY IF INCOMPLETE
        if [[ "$lh_ok" == "FALSE" || "$rh_ok" == "FALSE" ]]; then
            echo "⚠️  INCOMPLETE — Cleaning: $subj_name $ses_name"
            cleaned="TRUE"

            rm -f "$mri"/lh.hippoAmygLabels-T1.v21.*
            rm -f "$mri"/rh.hippoAmygLabels-T1.v21.*
            rm -f "$mri"/lh.hippoSfVolumes-T1.v21.txt
            rm -f "$mri"/rh.hippoSfVolumes-T1.v21.txt
            rm -f "$mri"/lh.amygNucVolumes-T1.v21.txt
            rm -f "$mri"/rh.amygNucVolumes-T1.v21.txt
        fi

        echo "$subj_name,$ses_name,$lh_ok,$rh_ok,$cleaned" >> "$OUTPUT_CSV"
    done
done

echo "Done. Saved: $OUTPUT_CSV"
