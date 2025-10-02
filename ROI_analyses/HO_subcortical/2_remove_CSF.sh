#############################################
#
#	Generate Stats w fslmeants 
#/Volumes/helpern_share/Image_Analysis_Scripts/ROI_analyses/HO_subcortical/2_remove_CSF.sh /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/dti-tk/dki_dti-tk/03_Analysis /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/dti-tk/dki_dti-tk/03_Analysis/00_Config_Files/ids.txt /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/dti-tk/dki_dti-tk/03_Analysis/00_Config_Files/mets.txt /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/dti-tk/dki_dti-tk/03_Analysis/00_Config_Files/rois.txt /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/dti-tk/dki_dti-tk/03_Analysis/04_ROI_Warps /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/dti-tk/dki_dti-tk/03_Analysis/05_Means_csf_masked 
#      
############################################# 

#!/usr/bin/env bash
set -euo pipefail

# ================================
# Usage
# ================================
# ./roi_pipeline.sh <base_dir> <ids_file> <dmets_file> <rois_file> <roi_warps_dir> <means_dir> [threshold]
#
# - base_dir      = main analysis directory (where 01_Scalar_Prep, 02_Tensors, etc. live)
# - ids_file      = text file with subject IDs, one per line
# - dmets_file    = text file with metric names (e.g. dti_ad, dti_rd, ...)
# - rois_file     = text file with ROI names (matching your masks)
# - roi_warps_dir = directory where warped ROIs are stored
# - means_dir     = directory where mean outputs should be written
# - threshold     = (optional) CSF threshold value, default = 1.5

if [ "$#" -lt 6 ] || [ "$#" -gt 7 ]; then
  echo "Usage: $0 <base_dir> <ids_file> <dmets_file> <rois_file> <roi_warps_dir> <means_dir> <means_dir> [threshold]"
  exit 1
fi

base=$1
ids_file=$2
dmets_file=$3
rois_file=$4
roi_warps=$5
means_dir=$6
threshold=${7:-1.5}   # default 1.5

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

mkdir -p "$roi_warps" "$means_dir" "$means_dir"

# ================================
# Individual CSF mask section
# ================================
mkdir -p "$roi_warps/ROIs_Individ_CSF_masked"
for i in "${ids[@]}"; do
  echo "Processing subject $i ..."
  fslmaths "$dki/${i}/dti_md_dtitk.nii.gz" -uthr "$threshold" -bin "$dki/${i}/csf_mask.nii"

  mkdir -p "$roi_warps/ROIs_Individ_CSF_masked/${i}"
  for r in "${rois[@]}"; do
    fslmaths "$roi_warps/${r}.nii.gz" -mul "$dki/${i}/csf_mask.nii" "$roi_warps/ROIs_Individ_CSF_masked/${i}/${r}.nii"
  done

  mkdir -p "$means_dir/${i}"
  for m in "${dmets[@]}"; do
    for r in "${rois[@]}"; do
      fslmeants \
        -i "$dki/${i}/${m}_dtitk_csfmasked.nii" \
        -o "$means_dir/${i}/${m}_${r}.txt" \
        -m "$roi_warps/ROIs_Individ_CSF_masked/${i}/${r}.nii"
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
  paste "$means_dir/${m}_"*.txt > "$means_dir/all_${m}.txt"
done

# ================================
# Mean CSF mask section
# ================================
fslmaths "$base/03_TBSS/stats/all_dti_md.nii.gz" \
  -Tmean "$base/03_TBSS/all_dti_md_mean.nii.gz"
fslmaths "$base/03_TBSS/all_dti_md_mean.nii.gz" \
  -uthr "$threshold" -bin \
  "$base/03_TBSS/all_dti_md_mean_thr${thr_label}.nii.gz"

mkdir -p "$roi_warps/ROIs_Mean_CSF_masked"
for i in "${ids[@]}"; do
  for r in "${rois[@]}"; do
    fslmaths "$base/03_TBSS/all_dti_md_mean_thr${thr_label}.nii.gz" \
      -mul "$roi_warps/${r}.nii.gz" \
      "$roi_warps/ROIs_Mean_CSF_masked/${r}.nii.gz"
  done
done

# Extract means using group mean CSF mask
mkdir -p "$means_dir/mean"
for m in "${dmets[@]}"; do
  for r in "${rois[@]}"; do
    fslmeants \
      -i "$base/03_TBSS/stats/all_${m}.nii.gz" \
      -o "$means_dir/mean/${m}_${r}.txt" \
      -m "$roi_warps/ROIs_Mean_CSF_masked/${r}.nii.gz"
  done
done

# Combine ROI text outputs into one file per metric
for m in "${dmets[@]}"; do
  paste "$means_dir/mean/${m}_"*.txt > "$means_dir/mean/all_${m}.txt"
done

#############################################
# Build CSV summary files
#############################################

build_csv() {
  src_dir="$1"    # e.g. $means_dir or $means_dir/mean
  out_csv="$2"    # output CSV path
  echo -n "SubjID,Metric" > "$out_csv"
  for r in "${rois[@]}"; do echo -n ",$r" >> "$out_csv"; done
  echo "" >> "$out_csv"

  for m in "${dmets[@]}"; do
    awk -v metric="$m" 'NR==FNR {ids[NR]=$1; next}
      {printf "%s,%s",ids[FNR],metric;
       for(i=1;i<=NF;i++){printf ",%s",$i}
       print ""}' "$ids_file" "$src_dir/all_${m}.txt" >> "$out_csv"
  done
}

# --- Create both CSVs ---
build_csv "$means_dir"          "$means_dir/Individual_CSF_Mask_Means.csv"
build_csv "$means_dir/mean"     "$means_dir/Mean_CSF_Mask_Means.csv"
