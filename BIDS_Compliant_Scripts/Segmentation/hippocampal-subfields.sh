#!/usr/bin/env bash
set -euo pipefail

###############################################
#  Check inputs
###############################################
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/freesurfer_7.2_directory/"
    exit 1
fi

BASE="$1"
OUTCSV="hippocampal_subfields_summary.csv"

echo "Using base directory: $BASE"
echo "Output CSV will be:  $OUTCSV"
echo

###############################################
#  Find subjects (GVFS-safe)
###############################################
subjects=()
for d in "$BASE"/sub-*; do
    [ -d "$d" ] && subjects+=("$(basename "$d")")
done

if [ "${#subjects[@]}" -eq 0 ]; then
    echo "ERROR: No subjects found under: $BASE"
    exit 1
fi

echo "Found ${#subjects[@]} subject(s)."
echo

HEADER_BUILT=0

###############################################
#  Main loop
###############################################
for subj in "${subjects[@]}"; do
    subjdir="${BASE}/${subj}"

    # enumerate sessions
    sessions=()
    for sespath in "$subjdir"/ses-*; do
        [ -d "$sespath" ] && sessions+=("$(basename "$sespath")")
    done

    if [ "${#sessions[@]}" -eq 0 ]; then
        echo "WARNING: no sessions found for $subj — skipping"
        continue
    fi

    for ses in "${sessions[@]}"; do
        sesdir="${subjdir}/${ses}"
        statsdir="${sesdir}/stats"

        lhstats="${statsdir}/hipposubfields.lh.T1.v21.stats"
        rhstats="${statsdir}/hipposubfields.rh.T1.v21.stats"

        echo "------------------------------------------------"
        echo "SUBJECT: $subj  SESSION: $ses"
        echo "------------------------------------------------"

        ###############################################
        #  Skip if already processed
        ###############################################
        if [ -f "$lhstats" ] && [ -f "$rhstats" ]; then
            echo "✓ Already processed — skipping segmentHA"
        else
            echo "→ Running segmentHA_T1.sh ..."

            # Freesurfer requirement: SUBJECT = session name, SUBJECTS_DIR = subject directory
            export SUBJECTS_DIR="$subjdir"

            if ! segmentHA_T1.sh "$ses" "$subjdir"; then
                echo "ERROR: segmentHA_T1.sh failed for $subj $ses"
                continue
            fi

            # recheck outputs
            if [ ! -f "$lhstats" ] || [ ! -f "$rhstats" ]; then
                echo "ERROR: segmentHA_T1.sh completed but expected stats files missing."
                echo "Missing:"
                [ ! -f "$lhstats" ] && echo "  - LH stats"
                [ ! -f "$rhstats" ] && echo "  - RH stats"
                continue
            fi

            echo "✓ segmentHA_T1.sh completed."
        fi

        ###############################################
        #  Build CSV header once
        ###############################################
        if [ $HEADER_BUILT -eq 0 ]; then
            labels=$(awk 'NF>=5 {print $5}' "$lhstats")

            header="SubjID,ses"
            for lbl in $labels; do header="${header},${lbl}_lh"; done
            for lbl in $labels; do header="${header},${lbl}_rh"; done

            echo "$header" > "$OUTCSV"
            HEADER_BUILT=1
            echo "→ CSV header created."
        fi

        ###############################################
        #  Extract values
        ###############################################
        lhvals=$(awk '{print $4}' "$lhstats" | paste -sd "," -)
        rhvals=$(awk '{print $4}' "$rhstats" | paste -sd "," -)

        echo "${subj},${ses},${lhvals},${rhvals}" >> "$OUTCSV"
        echo "✓ Added to CSV."

    done
done

echo
echo "==========================================="
echo "DONE! CSV generated: $OUTCSV"
echo "==========================================="
