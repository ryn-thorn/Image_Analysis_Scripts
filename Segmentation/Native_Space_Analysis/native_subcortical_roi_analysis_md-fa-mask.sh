#!/usr/local/bin/bash
set -euo pipefail
#set -x

#############################################
# Native Space Subcortical ROI Analysis (BIDS-Compatible)
# Version: 2.2 | FA and MD mask
#############################################

# ============================================
# Usage
# ============================================
if [[ $# -lt 5 || $# -gt 6 ]]; then
    echo "Usage: $0 <FS_BASE> <OUT_BASE> <DKI_BASE> <RAW_BASE> <PY_THRESHOLD> [FORCE]"
    exit 1
fi

FS_BASE="$1"
OUT_BASE="$2"
DKI_BASE="$3"
RAW_BASE="$4"
PY_THRESHOLD="$5"
FORCE=${6:-false}

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
# Main Loop: Process each subject/session
# ============================================
for aseg_path in "${ASEG_PATHS[@]}"; do

    mri_dir=$(dirname "$aseg_path")
    ses=$(basename "$(dirname "$mri_dir")")
    subj_dir=$(dirname "$(dirname "$mri_dir")")
    subj=$(basename "$subj_dir")

    echo "=== Processing $subj / $ses ==="

    fs_t1_mgz="${mri_dir}/T1.mgz"
    if [[ ! -f "$fs_t1_mgz" ]]; then
        echo "Missing FS T1 for $subj/$ses" >> "$LOGFILE"
        continue
    fi

    subj_out="${OUT_BASE}/${subj}/${ses}"
    mkdir -p "$subj_out"

    dki_dir="${DKI_BASE}/${subj}/${ses}"
    metrics_dir="${dki_dir}/metrics"

    # --------------------------------------------
    # Convert FreeSurfer volumes
    # --------------------------------------------
    fs_t1_nii="${subj_out}/FS_T1.nii.gz"
    aseg_nii="${subj_out}/aparc+aseg.nii.gz"

    if [[ "$FORCE" == true || ! -f "$fs_t1_nii" ]]; then
        mri_convert "$fs_t1_mgz" "$fs_t1_nii"
    fi

    if [[ "$FORCE" == true || ! -f "$aseg_nii" ]]; then
        mri_convert "$aseg_path" "$aseg_nii"
    fi

    # --------------------------------------------
    # Find raw T1 in Raw_Data
    # --------------------------------------------
	t1_candidates=()
	while IFS= read -r f; do
		fname=$(basename "$f")
		# Match any T1-weighted file (BIDS standard)
		if [[ "$fname" =~ ([Tt]1w|T1).*\.nii(.gz)?$ ]]; then
			t1_candidates+=("$f")
		fi
	done < <(find "${RAW_BASE}/${subj}/${ses}" -type f -path "*anat/*" 2>/dev/null)
	
	if [[ ${#t1_candidates[@]} -eq 0 ]]; then
		echo "Missing raw T1 for $subj/$ses" >> "$LOGFILE"
		continue
	fi
	
	# Prefer .nii.gz over .nii
	t1_path=""
	for f in "${t1_candidates[@]}"; do
		[[ "$f" == *.nii.gz ]] && { t1_path="$f"; break; }
	done
	[[ -z "$t1_path" ]] && t1_path="${t1_candidates[0]}"
	
	[[ "$FORCE" == true || ! -f "${subj_out}/T1_raw.nii.gz" ]] && cp "$t1_path" "${subj_out}/T1_raw.nii.gz"

    # --------------------------------------------
    # Register FS → RAW T1
    # --------------------------------------------
    if [[ "$FORCE" == true || ! -f "${subj_out}/FS_T1_to_rawT1.mat" ]]; then
        flirt -in "$fs_t1_nii" -ref "${subj_out}/T1_raw.nii.gz" \
              -omat "${subj_out}/FS_T1_to_rawT1.mat" \
              -out "${subj_out}/FS_T1_in_rawT1.nii.gz"
    fi

    # --------------------------------------------
    # Transform aparc+aseg → RAW T1
    # --------------------------------------------
    aseg_in_rawT1="${subj_out}/aparc+aseg_in_rawT1.nii.gz"
    if [[ "$FORCE" == true || ! -f "$aseg_in_rawT1" ]]; then
        flirt -in "$aseg_nii" -ref "${subj_out}/T1_raw.nii.gz" \
              -applyxfm -init "${subj_out}/FS_T1_to_rawT1.mat" \
              -interp nearestneighbour -out "$aseg_in_rawT1"
    fi

    # --------------------------------------------
    # Split ROIs
    # --------------------------------------------
    for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
        id=${ROI_IDS[$i]}
        name=${ROI_NAMES[$i]}
        out="${subj_out}/${name}_rawT1.nii.gz"
        [[ "$FORCE" == true || ! -f "$out" ]] && fslmaths "$aseg_in_rawT1" -thr $id -uthr $id -bin "$out"
    done

    # --------------------------------------------
    # Compute B0 from DWI
    # --------------------------------------------
    dwi_file=$(find_nii "${dki_dir}/dwi_preprocessed.nii")
    if [[ -z "$dwi_file" ]]; then
        echo "No DWI file for $subj/$ses" >> "$LOGFILE"
        continue
    fi
    [[ "$FORCE" == true || ! -f "${subj_out}/B0.nii.gz" ]] && fslmaths "$dwi_file" -Tmean "${subj_out}/B0.nii.gz"

    # --------------------------------------------
    # Register RAW T1 → B0
    # --------------------------------------------
    if [[ "$FORCE" == true || ! -f "${subj_out}/rawT1_to_B0.mat" ]]; then
        flirt -in "${subj_out}/T1_raw.nii.gz" -ref "${subj_out}/B0.nii.gz" \
              -omat "${subj_out}/rawT1_to_B0.mat" \
              -out "${subj_out}/T1_raw_in_B0.nii.gz"
    fi

    # --------------------------------------------
    # Transform ROIs → B0
    # --------------------------------------------
    for name in "${ROI_NAMES[@]}"; do
        in_roi="${subj_out}/${name}_rawT1.nii.gz"
        out_roi="${subj_out}/${name}_B0.nii.gz"
        [[ "$FORCE" == true || ! -f "$out_roi" ]] && flirt -in "$in_roi" -ref "${subj_out}/B0.nii.gz" \
              -applyxfm -init "${subj_out}/rawT1_to_B0.mat" \
              -interp nearestneighbour -out "$out_roi"
    done

    # --------------------------------------------
    # Masking (MD ≤ 1.5 & FA ≤ 0.4)
    # --------------------------------------------
    md_file=$(find_nii "${metrics_dir}/dti_md.nii")
    fa_file=$(find_nii "${metrics_dir}/dti_fa.nii")
    combo_mask="${subj_out}/MDFA_mask.nii.gz"

    if [[ "$FORCE" == true || ! -f "$combo_mask" ]]; then
        if [[ -f "$md_file" && -f "$fa_file" ]]; then
            md_mask="${subj_out}/MD_mask.nii.gz"
            fslmaths "$md_file" -uthr 1.5 -bin "$md_mask"

            fa_thr="${subj_out}/FA_thr.nii.gz"
            fa_mask="${subj_out}/FA_mask.nii.gz"
            python "$PY_THRESHOLD" "$fa_file" "$fa_thr" 0.4
            fslmaths "$fa_thr" -bin "$fa_mask"

            fslmaths "$md_mask" -mul "$fa_mask" "$combo_mask"

            for name in "${ROI_NAMES[@]}"; do
                roi="${subj_out}/${name}_B0.nii.gz"
                masked="${subj_out}/${name}_B0_masked.nii.gz"
                [[ -f "$roi" ]] && fslmaths "$roi" -mul "$combo_mask" -bin "$masked"
            done
        else
            echo "Missing MD or FA for $subj/$ses" >> "$LOGFILE"
        fi
    fi

    # --------------------------------------------
    # Voxel counts CSV
    # --------------------------------------------
    if ! grep -q "^${subj},${ses}" "$VOX_CSV" || [[ "$FORCE" == true ]]; then
        vox_row="${subj},${ses}"
        for name in "${ROI_NAMES[@]}"; do
            roi="${subj_out}/${name}_B0_masked.nii.gz"
            voxels=$( [[ -f "$roi" ]] && fslstats "$roi" -V | awk '{print $1}' || echo "NA" )
            vox_row="${vox_row},${voxels}"
        done
        echo "$vox_row" >> "$VOX_CSV"
    fi

    # --------------------------------------------
    # ROI metric analysis CSV
    # --------------------------------------------
    for metric in dti_fa dti_md dki_mk; do
        metric_file=$(find_nii "${metrics_dir}/${metric}.nii")
        [[ ! -f "$metric_file" ]] && echo "Missing $metric for $subj/$ses" >> "$LOGFILE" && continue

        if grep -q "^${subj},${ses},${metric}" "$CSV" && [[ "$FORCE" != true ]]; then
            continue
        fi

        row="${subj},${ses},${metric}"
        for name in "${ROI_NAMES[@]}"; do
            roi="${subj_out}/${name}_B0_masked.nii.gz"
            mean=$( [[ -f "$roi" ]] && fslmeants -i "$metric_file" -m "$roi" || echo "NA" )
            row="${row},${mean}"
        done
        echo "$row" >> "$CSV"
    done

    echo "=== Finished $subj / $ses ==="
done

echo "✅ All sessions processed!"
echo "Metrics CSV: $CSV"
echo "Voxel counts CSV: $VOX_CSV"
echo "Missing inputs log: $LOGFILE"
