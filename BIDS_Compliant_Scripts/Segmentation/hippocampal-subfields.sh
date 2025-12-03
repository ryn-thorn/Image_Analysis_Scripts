#!/usr/bin/env bash
set -uo pipefail

###############################################################
# Parallel Freesurfer hippocampal subfield segmentation
# Handles BIDS-style sub-NNNN/ses-YY folders
# Uses FIFO semaphore for parallelization
###############################################################

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <freesurfer_base_dir> [MAX_JOBS]"
  exit 1
fi

FS_BASE="$1"            # e.g. /Volumes/vdrive/.../freesurfer_7.2
MAX_JOBS="${2:-4}"      # default max parallel jobs

BATCH_LOG="$FS_BASE/hippo_batch_$(date +%Y%m%d_%H%M%S).log"
echo "🔹 Batch log: $BATCH_LOG"
echo "Starting batch at $(date)" | tee -a "$BATCH_LOG"
echo "Max parallel jobs: $MAX_JOBS" | tee -a "$BATCH_LOG"

# ----------------- Find all subject/session directories -----------------
SESSION_DIRS=()
for subj in "$FS_BASE"/sub-*; do
    [[ -d "$subj" ]] || continue
    for ses in "$subj"/ses-*; do
        [[ -d "$ses" ]] || continue
        SESSION_DIRS+=("$ses")
    done
done

NUM_JOBS=${#SESSION_DIRS[@]}
echo "🧩 Found $NUM_JOBS sessions to process" | tee -a "$BATCH_LOG"
echo ">>> First 5 sessions:"
printf '%s\n' "${SESSION_DIRS[@]}" | head -n5 | tee -a "$BATCH_LOG"

# ----------------- FIFO semaphore -----------------
SEM_FIFO="/tmp/hippo_sem_$$"
trap 'rm -f "$SEM_FIFO"' EXIT
mkfifo "$SEM_FIFO"
exec 3<>"$SEM_FIFO"
for ((i=0;i<MAX_JOBS;i++)); do printf '%s\n' "token" >&3; done

acquire() { read -r -u 3 || return 1; }
release() { printf '%s\n' "token" >&3; }

# ----------------- Main loop -----------------
for ses_dir in "${SESSION_DIRS[@]}"; do
    ses_name=$(basename "$ses_dir")               # e.g. ses-Y0
    subj_id=$(basename "$(dirname "$ses_dir")")  # e.g. sub-1016

    LOG_FILE="$ses_dir/${subj_id}_${ses_name}_hippo.log"

    # skip if already done (check lh and rh stats)
    if [[ -f "$ses_dir/stats/hipposubfields.lh.T1.v21.stats" ]] && \
       [[ -f "$ses_dir/stats/hipposubfields.rh.T1.v21.stats" ]]; then
        echo "✅ $subj_id $ses_name already segmented, skipping" | tee -a "$BATCH_LOG"
        continue
    fi

    acquire

    {
        echo "🚀 [$(date)] Starting hippocampal segmentation: $subj_id $ses_name" | tee -a "$BATCH_LOG"

        # SUBJECTS_DIR points to the parent subject folder
        export SUBJECTS_DIR="$FS_BASE/$subj_id"

        # Call segmentHA_T1.sh on the session folder
        if ! segmentHA_T1.sh "$ses_name" >> "$LOG_FILE" 2>&1; then
            echo "❌ segmentHA_T1.sh failed for $subj_id $ses_name; see $LOG_FILE" | tee -a "$BATCH_LOG"
            echo "=== FAIL $subj_id $ses_name $(date) ===" >> "$LOG_FILE"
            release
            continue
        fi

        echo "✅ Completed hippocampal segmentation: $subj_id $ses_name" | tee -a "$BATCH_LOG"
        echo "=== DONE $subj_id $ses_name $(date) ===" >> "$LOG_FILE"

        release
    } &
done

wait
exec 3>&-
rm -f "$SEM_FIFO"

echo "🎉 All hippocampal segmentation jobs completed at $(date)" | tee -a "$BATCH_LOG"
