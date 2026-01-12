#!/usr/local/bin/bash
set -euo pipefail
#set -x

#############################################
# Native Space Subcortical ROI Analysis (BIDS-Compatible)
# Version: 2.2 | CSF mask (B0 space)
#############################################

# ============================================
# Usage
# ============================================
if [[ $# -lt 4 || $# -gt 5 ]]; then
    echo "Usage: $0 <FS_BASE> <OUT_BASE> <DKI_BASE> <RAW_BASE> [FORCE]"
    exit 1
fi

FS_BASE="$1"
OUT_BASE="$2"
DKI_BASE="$3"
RAW_BASE="$4"
FORCE=${5:-false}

# ============================================
# ROI IDs and Names
# ============================================
ROI_IDS=(10 11 12 13 17 18 24 26 28 49 50 51 52 53 54 58 60)
ROI_NAMES=(Left-Thalamus Left-Caudate Left-Putamen Left-Pallidum Left-Hippocampus Left-Amygdala CSF Left-Accumbens Left-VentralDC Right-Thalamus Right-Caudate Right-Putamen Right-Pallidum Right-Hippocampus Right-Amygdala Right-Accumbens Right-VentralDC)

# ============================================
# Logging & CSV Setup
# ============================================
LOGFILE="${OUT_BASE}/missing_inputs.log"
> "$LOGFILE"

CSV="${OUT_BASE}/roi_results.csv"
VOX_CSV="${OUT_BASE}/roi_voxel_counts.csv"

if [[ ! -f "$CSV" || "$FORCE" == true ]]; then
  {
    echo -n "SubjID,Session,Metric"
    for name in "${ROI_NAMES[@]}"; do
      echo -n ",${name}"
    done
    echo
  } > "$CSV"
fi

if [[ ! -f "$VOX_CSV" || "$FORCE" == true ]]; then
  {
    echo -n "SubjID,Session"
    for name in "${ROI_NAMES[@]}"; do
      echo -n ",${name}"
    done
    echo
  } > "$VOX_CSV"
fi

# ============================================
# Helper to find nii or nii.gz
# ============================================
find_nii() {
    local file="$1"
    if [ -f "$file" ]; then
        echo "$file"
    elif [ -f "${file}.gz" ]; then
        echo "${file}.gz"
    else
        echo ""
    fi
}

# ============================================
# Discover FreeSurfer sessions
# ============================================
echo "🔍 Scanning for FreeSurfer sessions..."
mapfile -t ASEG_PATHS < <(
    find "$FS_BASE" -type f -path "*/ses-*/mri/aparc+aseg.mgz" | sort
)

if [[ ${#ASEG_PATHS[@]} -eq 0 ]]; then
    echo "❌ No aparc+aseg.mgz files found under $FS_BASE"
    exit 1
fi

echo "✅ Found ${#ASEG_PATHS[@]} FreeSurfer session(s)."

# ============================================
# Main Loop
# ============================================
for aseg_path in "${ASEG_PATHS[@]}"; do

    mri_dir=$(dirname "$aseg_path")
    ses=$(basename "$(dirname "$mri_dir")")
    subj_dir=$(dirname "$(dirname "$mri_dir")")
    subj=$(basename "$subj_dir")

    echo "=== Processing $subj / $ses ==="

    fs_t1_mgz="${mri_dir}/T1.mgz"
    [[ ! -f "$fs_t1_mgz" ]] && echo "Missing FS T1 for $subj/$ses" >> "$LOGFILE" && continue

    subj_out="${OUT_BASE}/${subj}/${ses}"
    mkdir -p "$subj_out"

    dki_dir="${DKI_BASE}/${subj}/${ses}"
    metrics_dir="${dki_dir}/metrics"

    # --------------------------------------------
    # Convert FS volumes
    # --------------------------------------------
    fs_t1_nii="${subj_out}/FS_T1.nii.gz"
    aseg_nii="${subj_out}/aparc+aseg.nii.gz"

    [[ "$FORCE" == true || ! -f "$fs_t1_nii" ]] && mri_convert "$fs_t1_mgz" "$fs_t1_nii"
    [[ "$FORCE" == true || ! -f "$aseg_nii" ]] && mri_convert "$aseg_path" "$aseg_nii"

    # --------------------------------------------
    # Find raw T1
    # --------------------------------------------
    t1_candidates=()
    while IFS= read -r f; do
        [[ "$(basename "$f")" =~ ([Tt]1w|T1).*\.nii(.gz)?$ ]] && t1_candidates+=("$f")
    done < <(find "${RAW_BASE}/${subj}/${ses}" -type f -path "*anat/*" 2>/dev/null)

    [[ ${#t1_candidates[@]} -eq 0 ]] && echo "Missing raw T1 for $subj/$ses" >> "$LOGFILE" && continue

    t1_path=""
    for f in "${t1_candidates[@]}"; do [[ "$f" == *.nii.gz ]] && { t1_path="$f"; break; }; done
    [[ -z "$t1_path" ]] && t1_path="${t1_candidates[0]}"

    [[ "$FORCE" == true || ! -f "${subj_out}/T1_raw.nii.gz" ]] && cp "$t1_path" "${subj_out}/T1_raw.nii.gz"

    # --------------------------------------------
    # FS → raw T1
    # --------------------------------------------
    [[ "$FORCE" == true || ! -f "${subj_out}/FS_T1_to_rawT1.mat" ]] && \
        flirt -in "$fs_t1_nii" -ref "${subj_out}/T1_raw.nii.gz" \
              -omat "${subj_out}/FS_T1_to_rawT1.mat" \
              -out "${subj_out}/FS_T1_in_rawT1.nii.gz"

    # --------------------------------------------
    # aparc+aseg → raw T1
    # --------------------------------------------
    aseg_in_rawT1="${subj_out}/aparc+aseg_in_rawT1.nii.gz"
    [[ "$FORCE" == true || ! -f "$aseg_in_rawT1" ]] && \
        flirt -in "$aseg_nii" -ref "${subj_out}/T1_raw.nii.gz" \
              -applyxfm -init "${subj_out}/FS_T1_to_rawT1.mat" \
              -interp nearestneighbour -out "$aseg_in_rawT1"

    # --------------------------------------------
    # Split ROIs (raw T1)
    # --------------------------------------------
    for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
        id=${ROI_IDS[$i]}
        name=${ROI_NAMES[$i]}
        out="${subj_out}/${name}_rawT1.nii.gz"
        [[ "$FORCE" == true || ! -f "$out" ]] && \
            fslmaths "$aseg_in_rawT1" -thr $id -uthr $id -bin "$out"
    done

    # --------------------------------------------
    # Compute B0
    # --------------------------------------------
    dwi_file=$(find_nii "${dki_dir}/dwi_preprocessed.nii")
    [[ -z "$dwi_file" ]] && echo "No DWI for $subj/$ses" >> "$LOGFILE" && continue
    [[ "$FORCE" == true || ! -f "${subj_out}/B0.nii.gz" ]] && \
        fslmaths "$dwi_file" -Tmean "${subj_out}/B0.nii.gz"

    # --------------------------------------------
    # raw T1 → B0
    # --------------------------------------------
    [[ "$FORCE" == true || ! -f "${subj_out}/rawT1_to_B0.mat" ]] && \
        flirt -in "${subj_out}/T1_raw.nii.gz" -ref "${subj_out}/B0.nii.gz" \
              -omat "${subj_out}/rawT1_to_B0.mat" \
              -out "${subj_out}/T1_raw_in_B0.nii.gz"

    # --------------------------------------------
    # ROIs → B0
    # --------------------------------------------
    for name in "${ROI_NAMES[@]}"; do
        [[ "$FORCE" == true || ! -f "${subj_out}/${name}_B0.nii.gz" ]] && \
            flirt -in "${subj_out}/${name}_rawT1.nii.gz" -ref "${subj_out}/B0.nii.gz" \
                  -applyxfm -init "${subj_out}/rawT1_to_B0.mat" \
                  -interp nearestneighbour -out "${subj_out}/${name}_B0.nii.gz"
    done

    # --------------------------------------------
    # CSF masking (B0 space)
    # --------------------------------------------
    csf_roi="${subj_out}/CSF_B0.nii.gz"
    csf_inv="${subj_out}/CSF_inv_B0.nii.gz"

    if [[ ! -f "$csf_roi" ]]; then
        echo "Missing CSF ROI for $subj/$ses" >> "$LOGFILE"
    else
        [[ "$FORCE" == true || ! -f "$csf_inv" ]] && \
            fslmaths "$csf_roi" -bin -sub 1 -abs "$csf_inv"

        for name in "${ROI_NAMES[@]}"; do
            [[ "$name" == "CSF" ]] && continue
            roi="${subj_out}/${name}_B0.nii.gz"
            masked="${subj_out}/${name}_B0_masked.nii.gz"
            [[ -f "$roi" ]] && fslmaths "$roi" -mul "$csf_inv" -bin "$masked"
        done
    fi

    # --------------------------------------------
    # Voxel counts CSV
    # --------------------------------------------
    if ! grep -q "^${subj},${ses}" "$VOX_CSV" || [[ "$FORCE" == true ]]; then
        vox_row="${subj},${ses}"
        for name in "${ROI_NAMES[@]}"; do
            roi="${subj_out}/${name}_B0_masked.nii.gz"
            vox_row="${vox_row},$( [[ -f "$roi" ]] && fslstats "$roi" -V | awk '{print $1}' || echo "NA" )"
        done
        echo "$vox_row" >> "$VOX_CSV"
    fi

    # --------------------------------------------
    # ROI metrics CSV
    # --------------------------------------------
    for metric in dti_fa dti_md dki_mk; do
        metric_file=$(find_nii "${metrics_dir}/${metric}.nii")
        [[ ! -f "$metric_file" ]] && echo "Missing $metric for $subj/$ses" >> "$LOGFILE" && continue
        grep -q "^${subj},${ses},${metric}" "$CSV" && [[ "$FORCE" != true ]] && continue

        row="${subj},${ses},${metric}"
        for name in "${ROI_NAMES[@]}"; do
            roi="${subj_out}/${name}_B0_masked.nii.gz"
            row="${row},$( [[ -f "$roi" ]] && fslmeants -i "$metric_file" -m "$roi" || echo "NA" )"
        done
        echo "$row" >> "$CSV"
    done

    echo "=== Finished $subj / $ses ==="
done

echo "✅ All sessions processed!"
echo "Metrics CSV: $CSV"
echo "Voxel counts CSV: $VOX_CSV"
echo "Missing inputs log: $LOGFILE"
