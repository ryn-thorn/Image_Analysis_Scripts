##################################################
#
# Split registered HO subcortical atlas into discrete ROIS
# Usage: ./make_rois.sh /path/to/HO-subcortical_to_mean_FA.nii /path/to/output_dir
#
##################################################
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <input_nifti> <output_dir>"
  exit 1
fi

input=$1
rois=$2

mkdir -p "$rois"

# ROI label mapping (thr/uthr value → output name)
declare -A roi_map=(
  [1]=Left_Cerebral_White_Matter
  [2]=Left_Cerebral_Cortex
  [3]=Left_Lateral_Ventricle
  [4]=Left_Thalamus
  [5]=Left_Caudate
  [6]=Left_Putamen
  [7]=Left_Pallidum
  [8]=Brain-Stem
  [9]=Left_Hippocampus
  [10]=Left_Amygdala
  [11]=Left_Accumbens
  [12]=Right_Cerebral_White_Matter
  [13]=Right_Cerebral_Cortex
  [14]=Right_Lateral_Ventricle
  [15]=Right_Thalamus
  [16]=Right_Caudate
  [17]=Right_Putamen
  [18]=Right_Pallidum
  [19]=Right_Hippocampus
  [20]=Right_Amygdala
  [21]=Right_Accumbens
)

# Loop through all ROIs
for thr in "${!roi_map[@]}"; do
  out=$rois/${roi_map[$thr]}.nii
  echo "Creating $out ..."
  fslmaths "$input" -thr "$thr" -uthr "$thr" "$out"
done



