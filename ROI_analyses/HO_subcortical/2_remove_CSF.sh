#############################################
#
#	Generate Stats w fslmeants 
#	
#      
############################################# 

#!/usr/bin/env bash
set -euo pipefail

# ================================
# Usage
# ================================
# ./roi_pipeline.sh <base_dir> <ids_file> <dmets_file> <rois_file> <roi_warps_dir> <means_dir> <mean_csf_dir> [threshold]
#
# - base_dir      = main analysis directory (where 01_Scalar_Prep, 02_Tensors, etc. live)
# - ids_file      = text file with subject IDs, one per line
# - dmets_file    = text file with metric names (e.g. dti_ad, dti_rd, ...)
# - rois_file     = text file with ROI names (matching your masks)
# - roi_warps_dir = directory where warped ROIs are stored
# - means_dir     = directory where mean outputs should be written
# - mean_csf_dir  = directory where mean CSF mask outputs should be written
# - threshold     = (optional) CSF threshold value, default = 1.5

if [ "$#" -lt 7 ] || [ "$#" -gt 8 ]; then
  echo "Usage: $0 <base_dir> <ids_file> <dmets_file> <rois_file> <roi_warps_dir> <means_dir> <mean_csf_dir> [threshold]"
  exit 1
fi

base=$1
ids_file=$2
dmets_file=$3
rois_file=$4
roi_warps=$5
means_dir=$6
mean_csf_dir=$7
threshold=${8:-1.5}   # default 1.5

# Create a clean string for filenames (remove dot)
thr_label=$(echo "$threshold" | sed 's/\.//g')

tensors=$base/02_Tensors
dki=$base/01_Scalar_Prep

# ================================
# Load IDs, metrics, and ROIs safely
# ================================
ids=()
dmets=()
rois=()

# Load IDs
if [ -s "$ids_file" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && ids+=("$line")
  done < "$ids_file"
else
  echo "ERROR: ids_file ($ids_file) is missing or empty"
  exit 1
fi

# Load metrics
if [ -s "$dmets_file" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && dmets+=("$line")
  done < "$dmets_file"
else
  echo "ERROR: dmets_file ($dmets_file) is missing or empty"
  exit 1
fi

# Load ROIs
if [ -s "$rois_file" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && rois+=("$line")
  done < "$rois_file"
else
  echo "ERROR: rois_file ($rois_file) is missing or empty"
  exit 1
fi

mkdir -p "$roi_warps" "$means_dir" "$mean_csf_dir"

# ================================
# Individual CSF mask section
# ================================
for i in "${ids[@]}"; do
  echo "Processing subject $i ..."
  fslmaths "$dki/${i}/dti_md_dtitk.nii.gz" -uthr "$threshold" -bin "$dki/${i}/csf_mask.nii"

  for f in "${dmets[@]}"; do
    fslmaths "$dki/${i}/csf_mask.nii" -mul "$dki/${i}/${f}_dtitk.nii" "$dki/${i}/${f}_dtitk_csfmasked.nii"
  done

  mkdir -p "$roi_warps/${i}"
  for r in "${rois[@]}"; do
    fslmaths "$roi_warps/${r}.nii.gz" -mul "$dki/${i}/csf_mask.nii" "$roi_warps/${i}/${r}.nii"
  done

  mkdir -p "$means_dir/${i}"
  for m in "${dmets[@]}"; do
    for r in "${rois[@]}"; do
      fslmeants \
        -i "$dki/${i}/${m}_dtitk_csfmasked.nii" \
        -o "$means_dir/${i}/${m}_${r}.txt" \
        -m "$roi_warps/${i}/${r}.nii.gz"
    done
  done
done

# Concatenate results across subjects
for m in "${dmets[@]}"; do
  for r in "${rois[@]}"; do
    cat "$means_dir"/*/"${m}_${r}.txt" > "$means_dir/${m}_${r}.txt"
  done
done

# Merge ROIs for each metric
for m in "${dmets[@]}"; do
  paste "$means_dir/${m}_".*.txt > "$means_dir/all_${m}.txt"
done

# ================================
# Mean CSF mask section
# ================================
fslmaths "$mean_csf_dir/all_dti_md_mean.nii.gz" \
  -uthr "$threshold" -bin \
  "$mean_csf_dir/all_dti_md_mean_thr${thr_label}.nii.gz"

for i in "${ids[@]}"; do
  for r in "${rois[@]}"; do
    fslmaths "$mean_csf_dir/all_dti_md_mean_thr${thr_label}.nii.gz" \
      -mul "$roi_warps/${r}.nii.gz" \
      "$roi_warps/${r}_csf_masked.nii.gz"
  done
done

