#!/usr/bin/env bash
set -euo pipefail

# ------------------------------
# FSL-only centiloid preprocessing
# ------------------------------

print_usage() {
  echo ""
  echo "Usage:"
  echo "  $0 --fbp <FBP> --fbb <FBB> [--outdir <OUTDIR>]"
  echo "Optional: --mni <MNI_TEMPLATE>"
  exit 1
}

# ------------------------------
# Parse input arguments
# ------------------------------
DEFAULT_MNI="${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz"
MNI_TEMPLATE=""
OUTDIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fbp) FBP="$2"; shift 2;;
    --fbb) FBB="$2"; shift 2;;
    --outdir) OUTDIR="$2"; shift 2;;
    --mni) MNI_TEMPLATE="$2"; shift 2;;
    --help|-h) print_usage;;
    *) echo "Unknown argument: $1"; print_usage;;
  esac
done

# Required args check
if [[ -z "${FBP:-}" || -z "${FBB:-}" ]]; then
  echo "Missing required inputs."; print_usage
fi

# If OUTDIR not provided, set it to the directory containing the FBP input
if [[ -z "${OUTDIR}" ]]; then
  OUTDIR="$(dirname "${FBP}")"
fi

# MNI template fallback
if [[ -z "${MNI_TEMPLATE}" ]]; then
  if [[ -f "${DEFAULT_MNI}" ]]; then
    MNI_TEMPLATE="${DEFAULT_MNI}"
  else
    echo "Cannot find MNI template. Use --mni explicitly."
    exit 1
  fi
fi

# Prepare output dirs
mkdir -p "${OUTDIR}/linear_to_MNI"
mkdir -p "${OUTDIR}/fnirt_to_avg"

echo ""
echo "Using MNI template: ${MNI_TEMPLATE}"
echo ""

# ------------------------------
# 1) Linear FLIRT (FBP and FBB → MNI)
# ------------------------------
fbp_lin="${OUTDIR}/linear_to_MNI/fbp_to_MNI.nii.gz"
fbb_lin="${OUTDIR}/linear_to_MNI/fbb_to_MNI.nii.gz"
fbp_mat="${OUTDIR}/linear_to_MNI/fbp_to_MNI.mat"
fbb_mat="${OUTDIR}/linear_to_MNI/fbb_to_MNI.mat"

echo "1) Linear registration (FLIRT)..."

flirt -in "${FBP}" -ref "${MNI_TEMPLATE}" -out "${fbp_lin}"

flirt -in "${FBB}" -ref "${MNI_TEMPLATE}" -out "${fbb_lin}"

echo "   Done."

# ------------------------------
# 2) Create averaged PET template in MNI space
# ------------------------------
avg_pet="${OUTDIR}/avg_pet.nii.gz"
echo "2) Averaging FBP and FBB (in MNI space)..."

fslmaths "${fbp_lin}" -add "${fbb_lin}" -div 2 "${avg_pet}"
echo "   Created: ${avg_pet}"

# ------------------------------
# 3) Nonlinear FNIRT (orig PET → avg_pet)
# ------------------------------

echo "3) Nonlinear FNIRT (orig PET → avg_pet)..."

# First: affine-align original PET → MNI
fbp_aff="${OUTDIR}/fnirt_to_avg/fbp_aff_to_MNI.nii.gz"
fbb_aff="${OUTDIR}/fnirt_to_avg/fbb_aff_to_MNI.nii.gz"
fbp_aff_mat="${OUTDIR}/fnirt_to_avg/fbp_aff_to_MNI.mat"
fbb_aff_mat="${OUTDIR}/fnirt_to_avg/fbb_aff_to_MNI.mat"

flirt -in "${FBP}" -ref "${MNI_TEMPLATE}" -out "${fbp_aff}"

flirt -in "${FBB}" -ref "${MNI_TEMPLATE}" -out "${fbb_aff}"

# FNIRT
FNIRT_CFG="${FSLDIR}/etc/flirtsch/T1_2_MNI152_2mm.cnf"

fbp_fnirt_warp="${OUTDIR}/fnirt_to_avg/fbp_warpcoef.nii.gz"
fbp_fnirt="${OUTDIR}/fnirt_to_avg/fbp_to_avg_nonlin.nii.gz"

fbb_fnirt_warp="${OUTDIR}/fnirt_to_avg/fbb_warpcoef.nii.gz"
fbb_fnirt="${OUTDIR}/fnirt_to_avg/fbb_to_avg_nonlin.nii.gz"

echo "   FNIRT FBP..."
fnirt --in="${FBP}" --aff="${fbp_aff_mat}" --ref="${avg_pet}" \
      --iout="${fbp_fnirt}" --cout="${fbp_fnirt_warp}"

echo "   FNIRT FBB..."
fnirt --in="${FBB}" --aff="${fbb_aff_mat}" --ref="${avg_pet}" \
      --iout="${fbb_fnirt}" --cout="${fbb_fnirt_warp}"

echo "   Nonlinear warped images:"
echo "     ${fbp_fnirt}"
echo "     ${fbb_fnirt}"

echo ""
echo "DONE."
echo "Output directory: ${OUTDIR}"
