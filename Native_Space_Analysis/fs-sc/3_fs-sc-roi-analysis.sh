#!/bin/bash
set -e
set -u

##########################################################
# usage: 3_fs-sc-roi-analysis.sh /path/to/pyd_base /path/to/output /path/to/diffusion-means.csv
##########################################################

pyd_base="$1"
roi_base="$2"       # output folder from Script 1
csv_out="$3"

echo "SubjID,ROI," > "$csv_out"

# Get metric files headers (assuming same for all subjects)
metric_file=$(find "$pyd_base"/*/metrics/ -maxdepth 1 -name "dti_*.nii.gz" | head -n1)
metric_headers=$(basename $metric_file | sed 's/.nii.gz//')
metrics=$(ls "$pyd_base"/*/metrics/dti_*.nii.gz "$pyd_base"/*/metrics/dki_*.nii.gz 2>/dev/null | head -n0 | xargs -n1 basename | sed 's/.nii.gz//' | tr '\n' ',' | sed 's/,$//')
echo "SubjID,ROI,$metrics" > "$csv_out"

# Loop through subjects
for subj in "$pyd_base"/*; do
    subj_name=$(basename "$subj")
    echo "Processing $subj_name"

    subj_roi="$roi_base/$subj_name"
    [ -d "$subj_roi" ] || continue

    # Loop through each ROI
    for roi in "$subj_roi"/*.nii*; do
        roi_name=$(basename "$roi" | sed 's/.nii.*//')
        line="$subj_name,$roi_name"

        # Loop through metrics
        for metric in "$subj"/metrics/dti_*.nii.gz "$subj"/metrics/dki_*.nii.gz; do
            [ -f "$metric" ] || continue
            mean_val=$(fslmeants -i "$metric" -m "$roi")
            line="$line,$mean_val"
        done

        echo "$line" >> "$csv_out"
    done
done

echo "CSV created at $csv_out"
