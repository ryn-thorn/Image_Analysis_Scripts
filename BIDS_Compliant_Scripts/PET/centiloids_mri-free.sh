#!/usr/bin/env bash
set -euo pipefail

#
# Usage:
#   ./centiloid_groupwide_FSL.sh --fpb /path/to/FBP --fbb /path/to/FBB [--mni /path/to/MNI152_T1_1mm.nii.gz]


print_usage() {
  cat <<EOF
Usage:
  $0 --fpb <FBP_DIR> --fbb <FBB_DIR> [--mni <MNI_TEMPLATE>]

  --fpb   Directory containing subject subfolders for the "FBP" dataset.
  --fbb   Directory containing subject subfolders for the "FBB" dataset.
  --mni   Optional: path to MNI152_T1_1mm.nii.gz (defaults to \$FSLDIR/data/standard/MNI152_T1_1mm.nii.gz).
EOF
  exit 1
}

# -----------------------
# Parse args
# -----------------------
FBP_DIR=""
FBB_DIR=""
MNI_TEMPLATE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fpb) FBP_DIR="$2"; shift 2;;
    --fbb) FBB_DIR="$2"; shift 2;;
    --mni) MNI_TEMPLATE="$2"; shift 2;;
    --help|-h) print_usage;;
    *) echo "Unknown arg: $1"; print_usage;;
  esac
done

if [[ -z "${FBP_DIR}" || -z "${FBB_DIR}" ]]; then
  echo "Missing required arguments."
  print_usage
fi

# Default MNI if not supplied
DEFAULT_MNI="${FSLDIR:-}/data/standard/MNI152_T1_1mm.nii.gz"
if [[ -z "${MNI_TEMPLATE}" ]]; then
  if [[ -f "${DEFAULT_MNI}" ]]; then
    MNI_TEMPLATE="${DEFAULT_MNI}"
  else
    echo "MNI template not found. Please supply --mni /path/to/MNI152_T1_1mm.nii.gz"
    exit 1
  fi
fi

echo "FBP_DIR: ${FBP_DIR}"
echo "FBB_DIR: ${FBB_DIR}"
echo "MNI template: ${MNI_TEMPLATE}"
echo ""

# Filenames to look for in each modality folder
FBP_FILES=( "PiB.nii.gz" "florbetapir.nii.gz" )
FBB_FILES=( "PET_PIB.nii.gz" "PET_FBB.nii.gz" )

# Collect list of subject names present in both dirs
declare -a SUBJECTS=()
for subpath in "${FBP_DIR}"/*; do
  [[ -d "${subpath}" ]] || continue
  subj=$(basename "${subpath}")
  if [[ -d "${FBB_DIR}/${subj}" ]]; then
    SUBJECTS+=( "${subj}" )
  else
    echo "Warning: subject '${subj}' exists in FBP_DIR but not in FBB_DIR — skipping."
  fi
done

if [[ ${#SUBJECTS[@]} -eq 0 ]]; then
  echo "No matching subject subfolders found between FBP_DIR and FBB_DIR. Exiting."
  exit 1
fi

echo "Found ${#SUBJECTS[@]} matching subjects to process."
echo ""

# -----------------------
# 1) Linear registration for all PET files found (to MNI)
# -----------------------
linear_list=()   # collect linear-registered file paths for averaging

for subj in "${SUBJECTS[@]}"; do
  echo "Processing subject: ${subj}"
  subj_fbp_dir="${FBP_DIR}/${subj}"
  subj_fbb_dir="${FBB_DIR}/${subj}"

  # FBP files
  for fname in "${FBP_FILES[@]}"; do
    infile="${subj_fbp_dir}/${fname}"
    if [[ -f "${infile}" ]]; then
      outbase="${subj_fbp_dir}/${fname%.*}"   # output in same folder as input
      outimg="${outbase}_MNI.nii.gz"
      outmat="${outbase}_to_MNI.mat"
      echo "  FLIRT (FBP) ${infile} -> ${outimg}"
      flirt -in "${infile}" -ref "${MNI_TEMPLATE}" -out "${outimg}" -omat "${outmat}" 
      linear_list+=( "${outimg}" )
    else
      echo "  Missing (FBP) expected file: ${infile} -- skipping"
    fi
  done

  # FBB files
  for fname in "${FBB_FILES[@]}"; do
    infile="${subj_fbb_dir}/${fname}"
    if [[ -f "${infile}" ]]; then
      outbase="${subj_fbb_dir}/${fname%.*}"   # output in same folder as input
      outimg="${outbase}_MNI.nii.gz"
      outmat="${outbase}_to_MNI.mat"
      echo "  FLIRT (FBB) ${infile} -> ${outimg}"
      flirt -in "${infile}" -ref "${MNI_TEMPLATE}" -out "${outimg}" -omat "${outmat}" 
      linear_list+=( "${outimg}" )
    else
      echo "  Missing (FBB) expected file: ${infile} -- skipping"
    fi
  done

  echo ""
done

# Check we have something to average
if [[ ${#linear_list[@]} -eq 0 ]]; then
  echo "No linear-registered PETs were produced. Aborting."
  exit 1
fi

echo "Linear-registered images collected: ${#linear_list[@]}"

# -----------------------
# 2) Group-wide average of linear-registered images -> avg_pet.nii.gz
# -----------------------
# Use the FBP_DIR as output folder for avg_pet
avg_pet="${FBP_DIR}/avg_pet.nii.gz"
echo "Creating group average PET -> ${avg_pet}"

first="${linear_list[0]}"
cp "${first}" "${FBP_DIR}/_tmp_sum.nii.gz"

if [[ ${#linear_list[@]} -gt 1 ]]; then
  for ((i=1; i<${#linear_list[@]}; i++)); do
    fslmaths "${FBP_DIR}/_tmp_sum.nii.gz" -add "${linear_list[i]}" "${FBP_DIR}/_tmp_sum.nii.gz"
  done
fi

N=${#linear_list[@]}
fslmaths "${FBP_DIR}/_tmp_sum.nii.gz" -div "${N}" "${avg_pet}"
rm -f "${FBP_DIR}/_tmp_sum.nii.gz"

echo "  Created: ${avg_pet}"
echo ""

# -----------------------
# 3) FNIRT: for each original PET, affine init and warp -> avg_pet
# -----------------------
FNIRT_CFG="${FSLDIR}/etc/flirtsch/T1_2_MNI152_2mm.cnf"
if [[ ! -f "${FNIRT_CFG}" ]]; then
  echo "Warning: FNIRT config ${FNIRT_CFG} not found; fnirt may still run with defaults."
fi

for subj in "${SUBJECTS[@]}"; do
  echo "FNIRT registering subject: ${subj}"
  subj_fbp_dir="${FBP_DIR}/${subj}"
  subj_fbb_dir="${FBB_DIR}/${subj}"

  # FBP originals
  for fname in "${FBP_FILES[@]}"; do
    orig="${subj_fbp_dir}/${fname}"
    if [[ -f "${orig}" ]]; then
      outpref="${subj_fbp_dir}/${fname%.*}"
      aff_out="${outpref}_aff.nii.gz"
      aff_mat="${outpref}_aff.mat"
      fnirt_iout="${outpref}_to_avg_nonlin.nii.gz"
      fnirt_warp="${outpref}_warpcoef.nii.gz"

      echo "  Affine (FLIRT) init: ${orig} -> MNI"
      flirt -in "${orig}" -ref "${MNI_TEMPLATE}" -out "${aff_out}" -omat "${aff_mat}" -dof 12 -cost corratio -interp trilinear

      echo "  FNIRT: ${orig} -> ${avg_pet}  (output: ${fnirt_iout})"
      fnirt --in="${orig}" --aff="${aff_mat}" --ref="${avg_pet}" --iout="${fnirt_iout}" --cout="${fnirt_warp}" 
    else
      echo "  Missing original (FBP): ${orig} -- skipping"
    fi
  done

  # FBB originals
  for fname in "${FBB_FILES[@]}"; do
    orig="${subj_fbb_dir}/${fname}"
    if [[ -f "${orig}" ]]; then
      outpref="${subj_fbb_dir}/${fname%.*}"
      aff_out="${outpref}_aff.nii.gz"
      aff_mat="${outpref}_aff.mat"
      fnirt_iout="${outpref}_to_avg_nonlin.nii.gz"
      fnirt_warp="${outpref}_warpcoef.nii.gz"

      echo "  Affine (FLIRT) init: ${orig} -> MNI"
      flirt -in "${orig}" -ref "${MNI_TEMPLATE}" -out "${aff_out}" -omat "${aff_mat}" -dof 12 -cost corratio -interp trilinear

      echo "  FNIRT: ${orig} -> ${avg_pet}  (output: ${fnirt_iout})"
      fnirt --in="${orig}" --aff="${aff_mat}" --ref="${avg_pet}" --iout="${fnirt_iout}" --cout="${fnirt_warp}" 
    else
      echo "  Missing original (FBB): ${orig} -- skipping"
    fi
  done

  echo ""
done

echo "All done."
echo "Group average PET: ${avg_pet}"
