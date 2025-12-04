#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <freesurfer_base_dir>"
    exit 1
fi

FS_BASE="$1"
OUT_CSV="$FS_BASE/hippocampal_completion_$(date +%Y%m%d_%H%M%S).csv"

echo "subj,ses,lh_complete,rh_complete" > "$OUT_CSV"

# Expected 22 labels from segmentHA_T1.sh outputs
expected_labels=(
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

check_stats_file () {
    local file="$1"

    [[ -f "$file" ]] || { echo "FALSE"; return; }

    # count how many expected labels appear
    local missing=0
    for label in "${expected_labels[@]}"; do
        if ! grep -q "$label" "$file"; then
            missing=$((missing+1))
        fi
    done

    if [[ "$missing" -eq 0 ]]; then
        echo "TRUE"
    else
        echo "FALSE"
    fi
}

for subj_dir in "$FS_BASE"/sub-*; do
    [[ -d "$subj_dir" ]] || continue
    subj=$(basename "$subj_dir")

    for ses_dir in "$subj_dir"/ses-*; do
        [[ -d "$ses_dir" ]] || continue
        ses=$(basename "$ses_dir")

        lh="$ses_dir/stats/hipposubfields.lh.T1.v21.stats"
        rh="$ses_dir/stats/hipposubfields.rh.T1.v21.stats"

        lh_ok=$(check_stats_file "$lh")
        rh_ok=$(check_stats_file "$rh")

        echo "$subj,$ses,$lh_ok,$rh_ok" >> "$OUT_CSV"
    done
done

echo "✅ Completion summary written to:"
echo "   $OUT_CSV"
