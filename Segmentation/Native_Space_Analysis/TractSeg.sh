#!/usr/bin/env bash
set -euo pipefail

##########################################
# Paths and environment
##########################################
cd /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/

base="tractseg+dtitk_y0y2"
ws="dki_dti-tk_within_subject/03_Analysis"
ws_mets="$ws/03_Metric_Transform"
ws_tens="$ws/02_Tensors"

ID_file="$base/01_Protocols/ids.txt"
ids_all=($(cat "$ID_file"))

ID_file_bl="$base/01_Protocols/ids_bl.txt"
ids_bl=($(cat "$ID_file_bl"))

mkdir -p "$base/03_Analysis" "$base/04_Summary" "$base/03_Analysis/01_TractSeg" "$base/03_Analysis/02_Tractometry"

##########################################
# Helpers
##########################################

# Split 4D DWI into 3D volumes
split_dwi() {
    local subj="$1"
    fslsplit "$ws/01_Tensor_Prep/${subj}/dwi_preprocessed.nii" \
             "$ws/01_Tensor_Prep/${subj}/" -t
}

# Warp all 3D volumes into ws space
warp_dwi() {
    local subj="$1"
    for idx in $(seq -w 000 199); do
        local f="$ws/01_Tensor_Prep/${subj}/${idx}.nii.gz"
        [[ -f "$f" ]] || continue

        local tmp="${f%.nii.gz}_000.nii.gz"
        local out="${f%.nii.gz}_ws.nii.gz"

        TVAdjustVoxelspace -in "$f" -origin 0 0 0 -out "$tmp"
        deformationScalarVolume -in "$tmp" \
            -trans "$ws_tens/${subj}/${subj}_combined.df.nii.gz" \
            -target "$ws_tens/${subj}/mean_initial.nii.gz" \
            -out "$out"
    done
}

# Merge warped 3Ds back into a 4D
merge_dwi() {
    local subj="$1"
    local outdir="$base/03_Analysis/${subj}"
    mkdir -p "$outdir"
    fslmerge -t "$outdir/dwi_preprocessed_ws.nii.gz" \
             "$ws/01_Tensor_Prep/${subj}"/0*_ws.nii.gz
    rm "$ws/01_Tensor_Prep/${subj}"/0*_ws.nii.gz \
       "$ws/01_Tensor_Prep/${subj}"/0*_000.nii.gz
}

# Run TractSeg + Tractometry
run_tractseg() {
    local subj="$1"

    echo "Running TractSeg for $subj"

    local subj_dir="$base/03_Analysis/${subj}"
    local ts_out="$base/03_Analysis/01_TractSeg/${subj}"
    local tm_out="$base/03_Analysis/02_Tractometry/${subj}"
    mkdir -p "$ts_out" "$tm_out"

    # Threshold + sanitize metrics
    fslmaths "$ws_mets/${subj}/dki_mk_ws.nii.gz" -thr 0 -uthr 3 -nan "$ws_mets/${subj}/dki_mk_ws.nii.gz"
    fslmaths "$ws_mets/${subj}/dti_md_ws.nii.gz" -thr 0 -uthr 3 -nan "$ws_mets/${subj}/dti_md_ws.nii.gz"
    fslmaths "$ws_mets/${subj}/dti_fa_ws.nii.gz" -nan "$ws_mets/${subj}/dti_fa_ws.nii.gz"

    # Copy bvals/bvecs
    cp "$ws/01_Tensor_Prep/${subj}/dwi_preprocessed.bvec" "$subj_dir/dwi_preprocessed_ws.bvecs"
    cp "$ws/01_Tensor_Prep/${subj}/dwi_preprocessed.bval" "$subj_dir/dwi_preprocessed_ws.bvals"

    # Run TractSeg pipeline
    TractSeg -i "$subj_dir/dwi_preprocessed_ws.nii.gz" -o "$ts_out" --raw_diffusion_input --output_type tract_segmentation
    TractSeg -i "$ts_out/peaks.nii.gz" -o "$ts_out" --output_type endings_segmentation
    TractSeg -i "$ts_out/peaks.nii.gz" -o "$ts_out" --output_type TOM
    Tracking -i "$ts_out/peaks.nii.gz" -o "$ts_out" --nr_fibers 5000

    # Run Tractometry for metrics
    for f in dti_fa dti_md dki_mk; do
        Tractometry -i "$ts_out/TOM_trackings/" \
                    -o "$tm_out/Tractometry_${f}.csv" \
                    -e "$ts_out/endings_segmentations/" \
                    -s "$ws_mets/${subj}/${f}_ws.nii.gz"
    done
}

# Group plotting
plot_group_results() {
    local metrics=("dti_md" "dki_mk" "dti_fa")
    for f in "${metrics[@]}"; do
        sed "s/METRIC/$f/g" "$base/01_Protocols/subjects_nometa.txt" > "$base/01_Protocols/subjects_5_${f}.txt"

        local out="$base/04_Summary/no_metadata/tractometry_result_${f}.png"
        mkdir -p "$(dirname "$out")"

        if [[ "$f" == "dti_fa" ]]; then
            plot_tractometry_results -i "$base/01_Protocols/subjects_5_${f}.txt" -o "$out" --mc --range "0 1"
        else
            plot_tractometry_results -i "$base/01_Protocols/subjects_5_${f}.txt" -o "$out" --mc --range "0 3"
        fi
    done
}

##########################################
# 1. Preprocess DWIs
##########################################
for subj in "${ids_all[@]}"; do
    echo "Splitting $subj"
    split_dwi "$subj"
done

for subj in "${ids_bl[@]}"; do
    echo "Warping baseline $subj"
    warp_dwi "$subj"
done

for subj in "${ids_all[@]}"; do
    echo "Merging $subj"
    merge_dwi "$subj"
done

##########################################
# 2. TractSeg + Tractometry
##########################################
source TractSeg/bin/activate

for subj in "${ids_all[@]}"; do
    run_tractseg "$subj"
done

##########################################
# 3. Group plotting
##########################################
plot_group_results
