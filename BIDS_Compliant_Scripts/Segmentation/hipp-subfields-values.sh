#!/usr/bin/env bash
set -eo pipefail

############################################################
# Usage:
#   ./hippo_stats_to_csv.sh <freesurfer_base_dir> <output_csv>
#
# Description:
#   - Finds all hipposubfields.*.stats files under BIDS FreeSurfer outputs
#   - Extracts volume (4th column) for each subfield
#   - Combines left (lh) and right (rh) into a single CSV
#   - Output columns: Sub,Ses,Hippocampal_tail_lh,...,Whole_hippocampus_rh
############################################################

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <freesurfer_base_dir> <output_csv>"
    exit 1
fi

FS_BASE="$1"
OUT_CSV="$2"

# Temporary files for building CSV
tmp_header=$(mktemp)
tmp_rows=$(mktemp)

# Find all hipposubfields stats files
mapfile -t stats_files < <(find "$FS_BASE" -type f -name "hipposubfields.*.stats" | sort)

if [[ ${#stats_files[@]} -eq 0 ]]; then
    echo "❌ No hipposubfields stats files found under $FS_BASE"
    exit 1
fi

declare -A data
declare -A headers_lh
declare -A headers_rh
declare -A seen_keys
sub_ses_list=()

# #############################
# Parse all stats files
# #############################
for f in "${stats_files[@]}"; do
    # Correctly extract subj and ses based on BIDS FS structure:
    # FS_BASE/sub-XXXX/ses-YY/stats/hipposubfields.*.stats
    subj=$(basename "$(dirname "$(dirname "$(dirname "$f")")")")   # sub-XXXX
    ses=$(basename "$(dirname "$(dirname "$f")")")                   # ses-YY
    hemi=$(basename "$f" | cut -d'.' -f2)                            # lh or rh
    key="${subj}_${ses}"

    # Keep track of unique sub/session pairs
    if [[ -z "${seen_keys[$key]+x}" ]]; then
        seen_keys[$key]=1
        sub_ses_list+=("$key")
    fi

    while read -r line; do
        [[ "$line" =~ ^# ]] && continue  # skip comments
        vol=$(echo "$line" | awk '{print $4}')
        name=$(echo "$line" | awk '{print $5}')
        data["${key}_${name}_${hemi}"]=$vol
        if [[ "$hemi" == "lh" ]]; then
            headers_lh["$name"]=1
        else
            headers_rh["$name"]=1
        fi
    done < "$f"
done

# #############################
# Build CSV header
# #############################
echo -n "Sub,Ses" > "$tmp_header"
for h in $(printf "%s\n" "${!headers_lh[@]}" | sort); do
    echo -n ",${h}_lh" >> "$tmp_header"
done
for h in $(printf "%s\n" "${!headers_rh[@]}" | sort); do
    echo -n ",${h}_rh" >> "$tmp_header"
done
echo "" >> "$tmp_header"

# #############################
# Build CSV rows
# #############################
for key in "${sub_ses_list[@]}"; do
    subj=$(echo "$key" | cut -d'_' -f1)
    ses=$(echo "$key" | cut -d'_' -f2)
    echo -n "$subj,$ses" >> "$tmp_rows"

    # Left hemisphere volumes
    for h in $(printf "%s\n" "${!headers_lh[@]}" | sort); do
        vol="${data[${key}_${h}_lh]:-NA}"
        echo -n ",$vol" >> "$tmp_rows"
    done
    # Right hemisphere volumes
    for h in $(printf "%s\n" "${!headers_rh[@]}" | sort); do
        vol="${data[${key}_${h}_rh]:-NA}"
        echo -n ",$vol" >> "$tmp_rows"
    done
    echo "" >> "$tmp_rows"
done

# #############################
# Combine header and rows
# #############################
cat "$tmp_header" "$tmp_rows" > "$OUT_CSV"
rm -f "$tmp_header" "$tmp_rows"

echo "✅ CSV written to $OUT_CSV"
