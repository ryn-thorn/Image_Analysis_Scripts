#!/bin/bash
set -euo pipefail
#set -x

#############################################
# Native Space Subcortical ROI Analysis
# Version: 1.4
#############################################

# ============================================
# Usage
# ============================================
if [[ $# -lt 5 || $# -gt 6 ]]; then
    echo "Usage: $0 <FS_BASE> <OUT_BASE> <DKI_BASE> <RAW_BASE> <PY_THRESHOLD> [--force]"
    echo "Example:"
    echo "  ./native_subcortical_roi_analysis.sh \\"
    echo "    /path/to/freesurfer \\"
    echo "    /path/to/output_dir \\"
    echo "    /path/to/pyd_dir \\"
    echo "    /path/to/raw_bids \\"
    echo "    /path/to/threshold_nifti.py \\"
    echo "    [--force]"
    exit 1
fi

FS_BASE="$1"
OUT_BASE="$2"
DKI_BASE="$3"
RAW_BASE="$4"
PY_THRESHOLD="$5"
FORCE="${6:-false}"

if [[ "$FORCE" == "--force" ]]; then
    FORCE=true
else
    FORCE=false
fi

# ============================================
# ROI IDs and Names
# ============================================
ROI_IDS=(10 11 12 13 17 18 24 26 28 49 50 51 52 53 54 58 60)
ROI_NAMES=(Left-Thalamus Left-Caudate Left-Putamen Left-Pallidum Left-Hippocampus Left-Amygdala CSF Left-Accumbens Left-VentralDC Right-Thalamus Right-Caudate Right-Putamen Right-Pallidum Right-Hippocampus Right-Amygdala Right-Accumbens Right-VentralDC)

# ============================================
# Logging & CSV Setup
# ============================================
LOGFILE="${OUT_BASE}/missing_T1.log"
> "$LOGFILE"

CSV="${OUT_BASE}/roi_results.csv"
VOX_CSV="${OUT_BASE}/roi_voxel_counts.csv"

# Metric means CSV header
if [[ ! -f "$CSV" || "$FORCE" == true ]]; then
  {
    echo -n "SubjID,Metric"
    for name in "${ROI_NAMES[@]}"; do
      echo -n ",${name}"
    done
    echo
  } > "$CSV"
fi

# Voxel counts CSV header
if [[ ! -f "$VOX_CSV" || "$FORCE" == true ]]; then
  {
    echo -n "SubjID"
    for name in "${ROI_NAMES[@]}"; do
      echo -n ",${name}"
    done
    echo
  } > "$VOX_CSV"
fi

# ============================================
# Helper function to find nii or nii.gz
# ============================================
find_nii() {
    file="$1"
    if [[ -f "${file}.gz" ]]; then
        echo "${file}.gz"
    elif [[ -f "$file" ]]; then
        echo "$file"
    else
        echo ""
    fi
}

# ============================================
# Main Loop
# ============================================
echo "Looking in $FS_BASE"

for subj_dir in "$FS_BASE"/*; do
    subj=$(basename "$subj_dir")
    aseg="${subj_dir}/mri/aparc+aseg.mgz"
    fs_t1_mgz="${subj_dir}/mri/T1.mgz"

    if [[ ! -f "$aseg" || ! -f "$fs_t1_mgz" ]]; then
        echo "Skipping $subj (missing aseg or T1.mgz)"
        continue
    fi

    echo "=== Processing $subj ==="
    subj_out="${OUT_BASE}/${subj}"
    mkdir -p "$subj_out"

    # --------------------------------------------
    # Convert aseg and T1 to NIfTI
    # --------------------------------------------
    aseg_nii="${subj_out}/aparc+aseg.nii.gz"
    fs_t1_nii="${subj_out}/FS_T1.nii.gz"

    if [[ "$FORCE" == true || ! -f "$fs_t1_nii" ]]; then
        echo "Running mri_convert (T1.mgz) ..."
        mri_convert "$fs_t1_mgz" "$fs_t1_nii"
    else
        echo "Skipping mri_convert (T1.mgz) — already exists"
    fi

    if [[ "$FORCE" == true || ! -f "$aseg_nii" ]]; then
        echo "Running mri_convert (aparc+aseg.mgz) ..."
        mri_convert "$aseg" "$aseg_nii"
    else
        echo "Skipping mri_convert (aparc+aseg.mgz) — already exists"
    fi

    # --------------------------------------------
    # Find raw T1 (robust version, fixed)
    # --------------------------------------------
    subj_pattern="${subj}"
    t1_path=""

    # Search recursively for an anat folder containing a T1 file
    t1_candidates=$(find "${RAW_BASE}" -type f -path "*/${subj_pattern}*/anat/*" \
        -iregex '.*t1.*mprage.*\.nii(\.gz)?$' 2>/dev/null || true)

    if [[ -z "$t1_candidates" ]]; then
        echo "Missing raw T1 for $subj" >> "$LOGFILE"
        continue
    fi

    # Handle multiple matches
    count=$(echo "$t1_candidates" | wc -l | tr -d ' ')
    if (( count > 1 )); then
        echo "⚠️  Multiple T1 candidates found for $subj:" >> "$LOGFILE"
        echo "$t1_candidates" >> "$LOGFILE"
        # Prefer .nii.gz if available
        t1_path=$(echo "$t1_candidates" | grep -m1 -E '\.nii\.gz$' || echo "$t1_candidates" | head -n1)
    else
        t1_path="$t1_candidates"
    fi

    # Copy T1 to subject output folder
    if [[ "$FORCE" == true || ! -f "${subj_out}/T1_raw.nii.gz" ]]; then
        cp "$t1_path" "${subj_out}/T1_raw.nii.gz"
    else
        echo "Skipping T1 copy — already exists"
    fi



    # --------------------------------------------
    # Register FS T1 to raw T1
    # --------------------------------------------
    if [[ "$FORCE" == true || ! -f "${subj_out}/FS_T1_to_rawT1.mat" ]]; then
        flirt -in "$fs_t1_nii" -ref "${subj_out}/T1_raw.nii.gz" \
              -omat "${subj_out}/FS_T1_to_rawT1.mat" \
              -out "${subj_out}/FS_T1_in_rawT1.nii.gz"
    else
        echo "Skipping FS_T1→rawT1 registration — already exists"
    fi

    # --------------------------------------------
    # Apply transform to aparc+aseg
    # --------------------------------------------
    aseg_in_rawT1="${subj_out}/aparc+aseg_in_rawT1.nii.gz"
    if [[ "$FORCE" == true || ! -f "$aseg_in_rawT1" ]]; then
        flirt -in "$aseg_nii" -ref "${subj_out}/T1_raw.nii.gz" \
              -applyxfm -init "${subj_out}/FS_T1_to_rawT1.mat" \
              -interp nearestneighbour -out "$aseg_in_rawT1"
    else
        echo "Skipping aseg→rawT1 transform — already exists"
    fi

	# --------------------------------------------
	# Split aparc+aseg into ROIs
	# --------------------------------------------
	roi_check=$(ls "${subj_out}"/*_rawT1.nii.gz 2>/dev/null | grep -v 'FS_T1_in_rawT1.nii.gz' || true)
	if [[ "$FORCE" == true || -z "$roi_check" ]]; then
		for i in $(seq 0 $((${#ROI_IDS[@]}-1))); do
			id=${ROI_IDS[$i]}
			name=${ROI_NAMES[$i]}
			out="${subj_out}/${name}_rawT1.nii.gz"
			fslmaths "$aseg_in_rawT1" -thr $id -uthr $id -bin "$out"
		done
	else
		echo "Skipping ROI splitting — already done"
	fi


    # --------------------------------------------
    # Get B0
    # --------------------------------------------
    dki_dir="${DKI_BASE}/${subj}"
    dwi_file=$(find_nii "${dki_dir}/dwi_preprocessed.nii")
    if [[ -z "$dwi_file" ]]; then
        echo "No DWI file for $subj"
        continue
    fi
    if [[ "$FORCE" == true || ! -f "${subj_out}/B0.nii.gz" ]]; then
        fslmaths "$dwi_file" -Tmean "${subj_out}/B0.nii.gz"
    else
        echo "Skipping B0 computation — already exists"
    fi

    # --------------------------------------------
    # Register raw T1 to B0
    # --------------------------------------------
    if [[ "$FORCE" == true || ! -f "${subj_out}/rawT1_to_B0.mat" ]]; then
        flirt -in "${subj_out}/T1_raw.nii.gz" -ref "${subj_out}/B0.nii.gz" \
              -omat "${subj_out}/rawT1_to_B0.mat" \
              -out "${subj_out}/T1_raw_in_B0.nii.gz"
    else
        echo "Skipping rawT1→B0 registration — already exists"
    fi

	
	# --------------------------------------------
	# Apply transform to ROIs
	# --------------------------------------------
	roi_b0_check=$(ls "${subj_out}"/*_B0.nii.gz 2>/dev/null | grep -v '^B0\.nii\.gz$' || true)
	if [[ "$FORCE" == true || -z "$roi_b0_check" ]]; then
		for name in "${ROI_NAMES[@]}"; do
			in_roi="${subj_out}/${name}_rawT1.nii.gz"
			out_roi="${subj_out}/${name}_B0.nii.gz"
			flirt -in "$in_roi" -ref "${subj_out}/B0.nii.gz" \
				  -applyxfm -init "${subj_out}/rawT1_to_B0.mat" \
				  -interp nearestneighbour -out "$out_roi"
		done
	else
		echo "Skipping ROI transforms to B0 — already done"
	fi


    # --------------------------------------------
    # Masking step (MD ≤ 1.5 AND FA ≤ 0.4)
    # --------------------------------------------
    metrics_dir="${dki_dir}/metrics"
    md_file=$(find_nii "${metrics_dir}/dti_md.nii")
    fa_file=$(find_nii "${metrics_dir}/dti_fa.nii")
    combo_mask="${subj_out}/MDFA_mask.nii.gz"

    if [[ "$FORCE" == true || ! -f "$combo_mask" ]]; then
        if [[ -f "$md_file" && -f "$fa_file" ]]; then
            md_mask="${subj_out}/MD_mask.nii.gz"
            fslmaths "$md_file" -uthr 1.5 -bin "$md_mask"

            fa_thr="${subj_out}/FA_thr.nii.gz"
            fa_mask="${subj_out}/FA_mask.nii.gz"
            python ${PY_THRESHOLD} "$fa_file" "$fa_thr" 0.4
            fslmaths "$fa_thr" -bin "$fa_mask"

            fslmaths "$md_mask" -mul "$fa_mask" "$combo_mask"

            for name in "${ROI_NAMES[@]}"; do
                roi="${subj_out}/${name}_B0.nii.gz"
                masked_roi="${subj_out}/${name}_B0_masked.nii.gz"
                if [[ -f "$roi" ]]; then
                    fslmaths "$roi" -mul "$combo_mask" -bin "$masked_roi"
                fi
            done
        else
            echo "Missing MD or FA metric for $subj — skipping mask step"
        fi
    else
        echo "Skipping mask step — already exists"
    fi

    # --------------------------------------------
    # Voxel count CSV
    # --------------------------------------------
    if ! grep -q "^${subj}," "$VOX_CSV" || [[ "$FORCE" == true ]]; then
        vox_row="${subj}"
        for name in "${ROI_NAMES[@]}"; do
            roi="${subj_out}/${name}_B0_masked.nii.gz"
            if [[ -f "$roi" ]]; then
                voxels=$(fslstats "$roi" -V | awk '{print $1}')
                vox_row="${vox_row},${voxels}"
            else
                vox_row="${vox_row},NA"
            fi
        done
        echo "$vox_row" >> "$VOX_CSV"
    else
        echo "Skipping voxel count logging — already present"
    fi

    # --------------------------------------------
    # ROI Analysis (FA, MD, MK)
    # --------------------------------------------
    for metric in dti_fa dti_md dki_mk; do
        metric_file=$(find_nii "${metrics_dir}/${metric}.nii")
        if [[ ! -f "$metric_file" ]]; then
            echo "Missing $metric for $subj"
            continue
        fi

        if grep -q "^${subj},${metric}" "$CSV" && [[ "$FORCE" != true ]]; then
            echo "Skipping ${metric} analysis — already logged"
            continue
        fi

        row="${subj},${metric}"
        for name in "${ROI_NAMES[@]}"; do
            roi="${subj_out}/${name}_B0_masked.nii.gz"
            if [[ -f "$roi" ]]; then
                mean=$(fslmeants -i "$metric_file" -m "$roi")
                row="${row},${mean}"
            else
                row="${row},NA"
            fi
        done

        echo "$row" >> "$CSV"
    done

    echo "=== Finished $subj ==="
done

echo "✅ Done!"
echo "Metrics CSV: $CSV"
echo "Voxel counts CSV: $VOX_CSV"
