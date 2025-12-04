#!/usr/bin/env bash
set -uo pipefail

############################################################
# Usage:
#   ./freesurfer-72-auto.sh <input_dir> <output_dir> [scratch_dir]
#
# Notes:
#   - Uses a FIFO semaphore for robust concurrency control
#   - Keeps per-subject logs and tmp dirs (no cleanup)
#   - Assumes recon-all from FS7.2 is already in the PATH
############################################################

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <input_dir> <output_dir> [scratch_dir]"
  exit 1
fi

input_dir="$1"
output_dir="$2"
scratch_base="${3:-/tmp/freesurfer_tmp}"
MAX_JOBS=4  # default 12, can be exported before calling

mkdir -p "$output_dir" "$scratch_base"

batch_log="$output_dir/recon_all_batch_$(date +%Y%m%d_%H%M%S).log"
echo "🔹 Batch log: $batch_log"
echo "Starting batch at $(date)" > "$batch_log"
echo "Scratch base: $scratch_base" | tee -a "$batch_log"
echo "Max jobs: $MAX_JOBS" | tee -a "$batch_log"

# --- Find T1s and filter Cor/Tra ---
mapfile -t all_t1_files < <(find "$input_dir" -type f \( -iname "*t1*.nii" -o -iname "*t1*.nii.gz" \))
mapfile -t t1_files < <(printf "%s\n" "${all_t1_files[@]}" | grep -viE "cor|tra" || true)

if [[ ${#t1_files[@]} -eq 0 ]]; then
  echo "❌ No usable T1 files found under $input_dir" | tee -a "$batch_log"
  exit 1
fi

# Deduplicate subjects: keep first T1 found for each subj
declare -A seen
subjects=()
t1_selected=()
for t1 in "${t1_files[@]}"; do
  subj=$(basename "$(dirname "$(dirname "$t1")")")
  if [[ "$subj" == "anat" || -z "$subj" ]]; then
    subj=$(basename "$(dirname "$t1")")
  fi
  if [[ -z "${seen[$subj]+x}" ]]; then
    seen[$subj]=1
    subjects+=("$subj")
    t1_selected+=("$t1")
  else
    # optional: log skipped duplicates
    echo "ℹ️ Skipping extra T1 for $subj: $t1" >> "$batch_log"
  fi
done

echo "🧩 Identified ${#subjects[@]} unique subjects." | tee -a "$batch_log"

# --- Create FIFO semaphore ---
sem_fifo="/tmp/freesurf_sem_$$"
trap 'rm -f "$sem_fifo"' EXIT
mkfifo "$sem_fifo"
# open file descriptor 3 for read/write on the fifo
exec 3<>"$sem_fifo"
# put $MAX_JOBS tokens into the semaphore
for ((i=0;i<MAX_JOBS;i++)); do
  printf '%s\n' "token" >&3
done

# Helper to acquire token: read one line from fd3
acquire() {
  read -r -u 3 || return 1
}

# Helper to release token: write one line back to fd3
release() {
  printf '%s\n' "token" >&3
}

# --- Main processing loop ---
for idx in "${!subjects[@]}"; do
  subj="${subjects[$idx]}"
  t1_file="${t1_selected[$idx]}"
  subj_out="$output_dir/$subj"
  subj_tmp="$scratch_base/$subj"
  subj_log="$output_dir/${subj}_recon.log"
  recon_log="$subj_tmp/$subj/scripts/recon-all.log"

  # Skip if already complete on output or tmp
  if [[ -f "$recon_log" ]] && tail -n 1 "$recon_log" | grep -q "finished without error"; then
    echo "✅ $subj appears complete (recon-all.log verified). Skipping." | tee -a "$batch_log"
    continue
  elif [[ -d "$subj_out" ]]; then
    echo "⚠️ $subj folder exists but not marked complete. Check $recon_log or delete to rerun." | tee -a "$batch_log"
    continue
  fi

  # Acquire a token (blocks until one is available)
  acquire

  # Launch job in background
  {
    slot_time="$(date +%Y%m%d_%H%M%S)"
    echo "🚀 [$(date)] Acquired slot — starting $subj with T1: $t1_file" | tee -a "$batch_log"
    mkdir -p "$subj_tmp"
    export SUBJECTS_DIR="$subj_tmp"

    echo "🏁 Running recon-all import for $subj (log: $subj_log)" | tee -a "$batch_log"
    echo "=== START ${subj} $(date) ===" >> "$subj_log"

    # import then full run (separate commands ensures safe behavior)
    if ! recon-all -i "$t1_file" -subjid "$subj" >> "$subj_log" 2>&1; then
      echo "❌ recon-all -i failed for $subj; see $subj_log" | tee -a "$batch_log"
      echo "=== FAIL ${subj} $(date) ===" >> "$subj_log"
      release
      continue
    fi

    echo "⚙️ Starting recon-all -all for $subj" >> "$subj_log"
    if ! recon-all -all -subjid "$subj" >> "$subj_log" 2>&1; then
      echo "❌ recon-all -all failed for $subj; see $subj_log" | tee -a "$batch_log"
      echo "=== FAIL ${subj} $(date) ===" >> "$subj_log"
      release
      continue
    fi

    # Verify completion and copy results if good
    if tail -n 1 "$recon_log" 2>/dev/null | grep -q "finished without error"; then
      rsync -a "$subj_tmp/$subj" "$output_dir/" --exclude="tmp"
      echo "✅ Finished $subj and copied to output." | tee -a "$batch_log"
      echo "=== DONE ${subj} $(date) ===" >> "$subj_log"
    else
      echo "❌ $subj did not finish cleanly; check $recon_log" | tee -a "$batch_log"
      echo "=== FAIL ${subj} $(date) ===" >> "$subj_log"
    fi

    # release the token for the next job
    release
  } &

done

# wait for all background jobs to complete
wait

# close fd3 and remove fifo
exec 3>&-
rm -f "$sem_fifo"

echo "🎉 All subjects processed. Completed at $(date)" | tee -a "$batch_log"
