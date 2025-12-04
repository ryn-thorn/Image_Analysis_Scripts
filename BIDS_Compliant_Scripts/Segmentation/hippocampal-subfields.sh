#!/usr/bin/env bash
set -uo pipefail

############################################################
# Usage:
#   ./segmentHA_batch.sh <freesurfer_base_dir>
#
# Description:
#   - Scans FreeSurfer 7.2 output directories in BIDS layout:
#       sub-*/ses-*
#   - Runs segmentHA_T1.sh on each session
#   - Parallelized using FIFO semaphore
############################################################

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <freesurfer_base_dir>"
  exit 1
fi

FS_BASE="$1"
MAX_JOBS="${MAX_JOBS:-4}"  # override with: export MAX_JOBS=8
BATCH_LOG="$FS_BASE/segmentHA_batch_$(date +%Y%m%d_%H%M%S).log"

echo "🔹 Batch log: $BATCH_LOG"
echo "Starting segmentHA batch at $(date)" > "$BATCH_LOG"
echo "Max jobs: $MAX_JOBS" | tee -a "$BATCH_LOG"

# ============================================================
# Step 1. Find all subject/session folders
# ============================================================
mapfile -t sub_ses_dirs < <(for sub in "$FS_BASE"/sub-*; do
    [ -d "$sub" ] || continue
    for ses in "$sub"/ses-*; do
        [ -d "$ses" ] && echo "$ses"
    done
done)


if [[ ${#sub_ses_dirs[@]} -eq 0 ]]; then
  echo "❌ No session directories found under $FS_BASE" | tee -a "$BATCH_LOG"
  exit 1
fi

echo "🧩 Identified ${#sub_ses_dirs[@]} sessions." | tee -a "$BATCH_LOG"

# ============================================================
# Step 2. Create FIFO semaphore for concurrency control
# ============================================================
sem_fifo="/tmp/segmentHA_sem_$$"
trap 'rm -f "$sem_fifo"' EXIT
mkfifo "$sem_fifo"
exec 3<>"$sem_fifo"
for ((i=0;i<MAX_JOBS;i++)); do printf '%s\n' "token" >&3; done

acquire() { read -r -u 3 || return 1; }
release() { printf '%s\n' "token" >&3; }

# ============================================================
# Step 3. Loop over each session and run segmentHA_T1.sh
# ============================================================
for ses_dir in "${sub_ses_dirs[@]}"; do
  subj=$(basename "$(dirname "$ses_dir")")   # sub-1001
  ses=$(basename "$ses_dir")                 # ses-Y0
  subj_ses="${subj}_${ses}"
  log_file="$ses_dir/segmentHA_${subj_ses}.log"
  subj_dir=$(dirname "$ses_dir")

  # Skip if already completed (check for hippocampal segmentation folder)
  if [[ -d "$ses_dir/stats/hipposubfields.lh.T1.v21.stats" ]]; then
    echo "✅ $subj_ses already has hippocampal segmentation. Skipping." | tee -a "$BATCH_LOG"
    continue
  fi

  acquire  # semaphore slot

  {
    echo "🚀 [$(date)] Starting $subj_ses" | tee -a "$BATCH_LOG"
    cd "$ses_dir" || { echo "❌ Cannot cd to $ses_dir"; release; exit 1; }

    if segmentHA_T1.sh "$ses" "$subj_dir" >> "$log_file" 2>&1; then
      echo "✅ Finished $subj_ses" | tee -a "$BATCH_LOG"
    else
      echo "❌ segmentHA_T1.sh failed for $subj_ses. Check $log_file" | tee -a "$BATCH_LOG"
    fi

    release
  } &
done

wait
exec 3>&-
rm -f "$sem_fifo"

echo "🎉 All sessions processed. Completed at $(date)" | tee -a "$BATCH_LOG"
