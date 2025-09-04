#######################################################
# Gross WM estimation using MK and MD thresholding
#######################################################
#
#   usage: /path/to/gross_wm_thr.sh /path/to/base_dir /path/to/out_dir /path/to/output.csv
#
#######################################################



if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <base_dir> <out_dir> <csv_output>"
    exit 1
fi

base_dir=$1
out_dir=$2
csv_output=$3

mkdir -p "$out_dir/1_masking"
mkdir -p "$out_dir/2_means"

for m in dti_fa dti_md dti_ad dti_rd dki_mk dki_rk dki_ak ; do
    mkdir -p "$out_dir/2_means/$m"
done

# loop de loop
for f in "$base_dir"/*/ ; do
    sub_id=$(basename "$f")
    mkdir -p "$out_dir/1_masking/$sub_id/metrics"
    
    fslmaths "$f/metrics/dki_mk.nii" -thr 0.9 -bin "$f/metrics/mk_0_9_mask.nii"
    fslmaths "$f/metrics/dti_md.nii" -uthr 1.5 -bin "$f/metrics/md_1_5_mask.nii"
    fslmaths "$f/metrics/mk_0_9_mask.nii" -mul "$f/metrics/md_1_5_mask.nii" \
        "$out_dir/1_masking/$sub_id/metrics/fa_mask.nii"
    fslmaths "$out_dir/1_masking/$sub_id/metrics/fa_mask.nii" -mul "$f/metrics/dti_fa.nii" \
        "$out_dir/1_masking/$sub_id/metrics/est_wm.nii"

    rm "$f/metrics/md_1_5_mask.nii"
    rm "$f/metrics/mk_0_9_mask.nii"

    # extract means
    for m in dti_fa dti_md dti_ad dti_rd dki_mk dki_rk dki_ak ; do
        fslmeants "$f/metrics/$m.nii" \
            -o "$out_dir/2_means/$m/${sub_id}.txt" \
            -m "$out_dir/1_masking/$sub_id/metrics/est_wm.nii"
    done
done

# gather all means into a CSV 
echo "sub_id,dti_fa,dti_md,dti_ad,dti_rd,dki_mk,dki_rk,dki_ak" > "$csv_output"
for f in "$base_dir"/*/ ; do
    sub_id=$(basename "$f")
    line="$sub_id"
    for m in dti_fa dti_md dti_ad dti_rd dki_mk dki_rk dki_ak ; do
        val=$(cat "$out_dir/2_means/$m/${sub_id}.txt")
        line="$line,$val"
    done
    echo "$line" >> "$csv_output"
done
