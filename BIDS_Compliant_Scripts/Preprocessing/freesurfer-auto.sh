#!/usr/bin/env bash
set -uo pipefail

############################################################
# Usage:
#   ./freesurfer-auto.sh <bids_input_dir> <output_dir> [scratch_dir]
#
# Description:
#   - Scans BIDS-style directories for T1w.nii(.gz) images:
#       sub-*/ses-*/anat/sub-*_ses-*_T1w.nii.gz
#   - Runs recon-all in parallel (max jobs = $MAX_JOBS)
#   - Skips subjects/sessions that already finished successfully
#
############################################################

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <bids_input_dir> <output_dir> [scratch_dir]"
  exit 1
fi

input_dir="$1"
output_dir="$2"
scratch_base="${3:-/tmp/freesurfer_tmp}"
MAX_JOBS="${MAX_JOBS:-4}"  # can override externally: export MAX_JOBS=8

mkdir -p "$output_dir" "$scratch_base"

batch_log="$output_dir/recon_all_batch_$(date +%Y%m%d_%H%M%S).log"
echo "🔹 Batch log: $batch_log"
echo "Starting batch at $(date)" > "$batch_log"
echo "Scratch base: $scratch_base" | tee -a "$batch_log"
echo "Max jobs: $MAX_JOBS" | tee -a "$batch_log"

# ############################################################
# Step 1. Find all T1w files in BIDS layout
# ############################################################
mapfile -t t1_files < <(find "$input_dir" -type f -iname "*_T1w.nii*" | sort)

if [[ ${#t1_files[@]} -eq 0 ]]; then
  echo "❌ No T1w images found under $input_dir" | tee -a "$batch_log"
  exit 1
fi

# ############################################################
# Step 2. Extract subject/session info
# ############################################################
subjects=()
sessions=()
t1_selected=()

declare -A seen

for t1 in "${t1_files[@]}"; do

  subj=$(basename "$(dirname "$(dirname "$t1")")")   # sub-1001
  ses=$(basename "$(dirname "$t1")")                 # ses-Y0
  subj_id="${subj}_${ses}"                           # unique pair (sub-1001_ses-Y0)

  # Avoid duplicates if multiple T1s exist per session
  if [[ -z "${seen[$subj_id]+x}" ]]; then
    seen[$subj_id]=1
    subjects+=("$subj")
    sessions+=("$ses")
    t1_selected+=("$t1")
  else
    echo "ℹ️ Skipping extra T1 for $subj_id: $t1" >> "$batch_log"
  fi
done

echo "🧩 Identified ${#t1_selected[@]} subject/session pairs." | tee -a "$batch_log"

# ############################################################
# Step 3. Create FIFO semaphore for concurrency control
# ############################################################
sem_fifo="/tmp/freesurf_sem_$$"
trap 'rm -f "$sem_fifo"' EXIT
mkfifo "$sem_fifo"
exec 3<>"$sem_fifo"
for ((i=0;i<MAX_JOBS;i++)); do printf '%s\n' "token" >&3; done

acquire() { read -r -u 3 || return 1; }
release() { printf '%s\n' "token" >&3; }

# ############################################################
# Step 4. Main loop over subject/session
# ############################################################
for idx in "${!t1_selected[@]}"; do
  subj="${subjects[$idx]}"
  ses="${sessions[$idx]}"
  t1_file="${t1_selected[$idx]}"
  subj_ses="${subj}_${ses}"

  subj_out="$output_dir/$subj_ses"
  subj_tmp="$scratch_base/$subj_ses"
  subj_log="$output_dir/${subj_ses}_recon.log"
  recon_log="$subj_tmp/$subj_ses/scripts/recon-all.log"

  # Skip if already complete
  if [[ -f "$recon_log" ]] && tail -n 1 "$recon_log" | grep -q "finished without error"; then
    echo "✅ $subj_ses already complete (verified)." | tee -a "$batch_log"
    continue
  elif [[ -d "$subj_out" ]]; then
    echo "⚠️ $subj_ses output exists but not complete. Check logs or remove to rerun." | tee -a "$batch_log"
    continue
  fi

  acquire  # acquire semaphore slot

  {
    echo "🚀 [$(date)] Starting $subj_ses using $t1_file" | tee -a "$batch_log"
    mkdir -p "$subj_tmp"
    export SUBJECTS_DIR="$subj_tmp"

    echo "🏁 Running recon-all import for $subj_ses (log: $subj_log)" | tee -a "$batch_log"
    echo "##= START ${subj_ses} $(date) ##=" >> "$subj_log"

    if ! recon-all -i "$t1_file" -subjid "$subj_ses" >> "$subj_log" 2>&1; then
      echo "❌ recon-all -i failed for $subj_ses; see $subj_log" | tee -a "$batch_log"
      echo "##= FAIL ${subj_ses} $(date) ##=" >> "$subj_log"
      release; continue
    fi

    echo "⚙️ Starting recon-all -all for $subj_ses" >> "$subj_log"
    if ! recon-all -all -subjid "$subj_ses" >> "$subj_log" 2>&1; then
      echo "❌ recon-all -all failed for $subj_ses; see $subj_log" | tee -a "$batch_log"
      echo "##= FAIL ${subj_ses} $(date) ##=" >> "$subj_log"
      release; continue
    fi

    if tail -n 1 "$recon_log" 2>/dev/null | grep -q "finished without error"; then
      rsync -a "$subj_tmp/$subj_ses" "$output_dir/" --exclude="tmp"
      echo "✅ Finished $subj_ses and copied results." | tee -a "$batch_log"
      echo "##= DONE ${subj_ses} $(date) ##=" >> "$subj_log"
    else
      echo "❌ $subj_ses did not finish cleanly; check $recon_log" | tee -a "$batch_log"
      echo "##= FAIL ${subj_ses} $(date) ##=" >> "$subj_log"
    fi

    release
  } &
done

wait
exec 3>&-
rm -f "$sem_fifo"

echo "🎉 All subjects/sessions processed. Completed at $(date)" | tee -a "$batch_log"