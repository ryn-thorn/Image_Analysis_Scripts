#!/bin/bash
set -e
set -u

##########################################################
# usage: 3_fs-sc-roi-analysis.sh /path/to/pyd_base /path/to/output /path/to/diffusion-means.csv /path/to/voxel-counts.csv
##########################################################

pyd_base="$1"
roi_base="$2"        # output folder from Script 2
csv_out="$3"
csv_vox="$4"

# Initialize CSV files
echo "SubjID,ROI" > "$csv_out"
echo "SubjID,ROI,NumVoxels" > "$csv_vox"

# Get metric headers (assuming same for all subjects)
metric_files=$(ls "$pyd_base"/*/metrics/dti_*.nii.gz "$pyd_base"/*/metrics/dki_*.nii.gz 2>/dev/null || true)
metrics=$(for f in $metric_files; do basename "$f" | sed 's/.nii.gz//'; done | tr '\n' ',' | sed 's/,$//')

echo "SubjID,ROI,$metrics" > "$csv_out"

# Loop through subjects
for subj in "$pyd_base"/*; do
    subj_name=$(basename "$subj")
    echo "Processing $subj_name"

    subj_roi="$roi_base/$subj_name"
    [ -d "$subj_roi" ] || continue

    # Loop through thresholded ROIs
    for roi in "$subj_roi"/*_thr.nii*; do
        roi_name=$(basename "$roi" | sed 's/_thr.nii.*//')
        line="$subj_name,$roi_name"

        # Loop through metrics
        for metric in "$subj"/metrics/dti_*.nii.gz "$subj"/metrics/dki_*.nii.gz; do
            [ -f "$metric" ] || continue
            mean_val=$(fslmeants -i "$metric" -m "$roi")
            line="$line,$mean_val"
        done

        # Write mean values to CSV
        echo "$line" >> "$csv_out"

        # ---- Voxel count for thresholded ROI ----
        voxels=$(fslstats "$roi" -V | awk '{print $1}')
        echo "$subj_name,$roi_name,$voxels" >> "$csv_vox"
    done
done

echo "CSV of means created at $csv_out"
echo "CSV of voxel counts created at $csv_vox"

