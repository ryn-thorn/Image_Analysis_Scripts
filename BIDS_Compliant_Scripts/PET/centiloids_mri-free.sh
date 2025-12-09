#!/usr/bin/env bash
set -euo pipefail

# ------------------------------
# FSL-only centiloid preprocessing
# ------------------------------

print_usage() {
  echo ""
  echo "Usage:"
  echo "  $0 --pet-fbp <FBP> --pet-fbb <FBB> --roi-cortical <ROI_CTX> --roi-wholecbl <ROI_WC> --outdir <OUTDIR>"
  echo "Optional: --mni <MNI_TEMPLATE>"
  exit 1
}

# ------------------------------
# Parse input arguments
# ------------------------------
DEFAULT_MNI="${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz"
MNI_TEMPLATE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pet-fbp) PET_FBP="$2"; shift 2;;
    --pet-fbb) PET_FBB="$2"; shift 2;;
    --roi-cortical) ROI_CTX="$2"; shift 2;;
    --roi-wholecbl) ROI_WC="$2"; shift 2;;
    --outdir) OUTDIR="$2"; shift 2;;
    --mni) MNI_TEMPLATE="$2"; shift 2;;
    --help|-h) print_usage;;
    *) echo "Unknown argument: $1"; print_usage;;
  esac
done

# Check required args
if [[ -z "${PET_FBP:-}" || -z "${PET_FBB:-}" || -z "${ROI_CTX:-}" || -z "${ROI_WC:-}" || -z "${OUTDIR:-}" ]]; then
  echo "Missing required inputs."; print_usage
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

mkdir -p "${OUTDIR}"/{linear_to_MNI,fnirt_to_avg,rois_to_MNI}

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

flirt -in "${PET_FBP}" -ref "${MNI_TEMPLATE}" -out "${fbp_lin}" 

flirt -in "${PET_FBB}" -ref "${MNI_TEMPLATE}" -out "${fbb_lin}" 

echo "   Done."

# ------------------------------
# 2) Create averaged PET template in MNI space
# ------------------------------
avg_pet="${OUTDIR}/avg_pet.nii.gz"
echo "2) Averaging FBP and FBB (in MNI space)..."

fslmaths "${fbp_lin}" -add "${fbb_lin}" -div 2 "${avg_pet}"
echo "   Created: ${avg_pet}"

# ------------------------------
# 3) Nonlinear FNIRT registration ORIGINAL PET → avg_pet
#     FNIRT requires both images in MNI space, so:
#     - first affine-align the original PET to MNI
#     - then run FNIRT using avg_pet as target
# ------------------------------

echo "3) Nonlinear FNIRT (orig PET → avg_pet)..."

# First: affine-align original PET → MNI (needed as FNIRT init)
fbp_aff="${OUTDIR}/fnirt_to_avg/fbp_aff_to_MNI.nii.gz"
fbb_aff="${OUTDIR}/fnirt_to_avg/fbb_aff_to_MNI.nii.gz"
fbp_aff_mat="${OUTDIR}/fnirt_to_avg/fbp_aff_to_MNI.mat"
fbb_aff_mat="${OUTDIR}/fnirt_to_avg/fbb_aff_to_MNI.mat"

flirt -in "${PET_FBP}" -ref "${MNI_TEMPLATE}" -out "${fbp_aff}" \
      -omat "${fbp_aff_mat}"

flirt -in "${PET_FBB}" -ref "${MNI_TEMPLATE}" -out "${fbb_aff}" \
      -omat "${fbb_aff_mat}"

# Now FNIRT using avg_pet as the target
# NOTE: FNIRT config designed for T1→MNI may not be ideal for PET→PET.
# The "T1_2_MNI152_2mm.cnf" config works reasonably in practice but can be tuned.
FNIRT_CFG="${FSLDIR}/etc/flirtsch/T1_2_MNI152_2mm.cnf"

fbp_fnirt_warp="${OUTDIR}/fnirt_to_avg/fbp_warpcoef.nii.gz"
fbp_fnirt="${OUTDIR}/fnirt_to_avg/fbp_to_avg_nonlin.nii.gz"

fbb_fnirt_warp="${OUTDIR}/fnirt_to_avg/fbb_warpcoef.nii.gz"
fbb_fnirt="${OUTDIR}/fnirt_to_avg/fbb_to_avg_nonlin.nii.gz"

echo "   FNIRT FBP..."
fnirt --in="${PET_FBP}" --aff="${fbp_aff_mat}" --ref="${avg_pet}" \
      --iout="${fbp_fnirt}" --cout="${fbp_fnirt_warp}" --config="${FNIRT_CFG}"

echo "   FNIRT FBB..."
fnirt --in="${PET_FBB}" --aff="${fbb_aff_mat}" --ref="${avg_pet}" \
      --iout="${fbb_fnirt}" --cout="${fbb_fnirt_warp}" --config="${FNIRT_CFG}"

echo "   Nonlinear warped images:"
echo "     ${fbp_fnirt}"
echo "     ${fbb_fnirt}"

# ------------------------------
# 4) Register ROIs to MNI
# ------------------------------
echo "4) ROI registration to MNI..."

roi_ctx_out="${OUTDIR}/rois_to_MNI/roi_ctx_to_MNI.nii.gz"
roi_wc_out="${OUTDIR}/rois_to_MNI/roi_WhlCbl_to_MNI.nii.gz"

flirt -in "${ROI_CTX}" -ref "${MNI_TEMPLATE}" -out "${roi_ctx_out}" 

flirt -in "${ROI_WC}" -ref "${MNI_TEMPLATE}" -out "${roi_wc_out}" 

echo "   ROI outputs:"
echo "     ${roi_ctx_out}"
echo "     ${roi_wc_out}"

echo ""
echo "Done. All results in: ${OUTDIR}"
