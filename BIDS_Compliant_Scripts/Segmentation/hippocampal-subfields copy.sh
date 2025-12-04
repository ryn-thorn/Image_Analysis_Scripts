#!/usr/bin/env bash
set -uo pipefail

############################################################
# Usage:
#   ./segmentHA_batch.sh <freesurfer_base_dir>
############################################################

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <freesurfer_base_dir>"
  exit 1
fi

MAIN_DIR="$1"

# List of files to check in the stats folder
REQUIRED_FILES=("hipposubfields.lh.T1.v21.stats" "hipposubfields.rh.T1.v21.stats") 


# Loop over each subject
for subfolder in "$MAIN_DIR"/sub-*; do
    [ -d "$subfolder" ] || continue
    sub_id=$(basename "$subfolder")
    echo "Processing subject: $sub_id"

    # Loop over each session
    for sesfolder in "$subfolder"/ses-*; do
        [ -d "$sesfolder" ] || continue
        ses_id=$(basename "$sesfolder")
        
        echo "  Processing session: $ses_id"
        
        # Remove IsRunning file if it exists
        file_to_remove="$sesfolder/scripts/IsRunningHPsubT1.lh+rh"
        if [ -f "$file_to_remove" ]; then
            echo "    Removing existing file: $file_to_remove"
            rm "$file_to_remove"
        fi

        stats_dir="$sesfolder/stats"

        # Check if all required files exist
        skip=false
        for f in "${REQUIRED_FILES[@]}"; do
            if [ ! -f "$stats_dir/$f" ]; then
                skip=false
                break
            else
                skip=true
            fi
        done

        if [ "$skip" = true ]; then
            echo "✅ $(basename "$subfolder") $(basename "$sesfolder") done, skipping."
            continue
        fi

        # Otherwise, run your tool
        echo "⚙️ Running segmentHA_T1.sh for (basename $subfolder) (basename $sesfolder)"
        segmentHA_T1.sh "$ses_id" "$subfolder"
    done
done
