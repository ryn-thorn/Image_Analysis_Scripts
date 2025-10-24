#!/usr/bin/env python3
"""
Split FreeSurfer aparc+aseg.nii into reference (cerebellar) and target VOIs
for Centiloid calibration or SUVR computation.

python3 make_gaain_vois.py \
  --aseg subject01_aparc+aseg.nii.gz \
  --outdir ./VOIs

"""

import argparse
import nibabel as nib
import numpy as np
import os

def main():
    parser = argparse.ArgumentParser(description="Generate VOI_ref and VOI NIfTIs from aparc+aseg.nii")
    parser.add_argument("--aseg", required=True, help="Path to aparc+aseg.nii or .nii.gz")
    parser.add_argument("--outdir", default=".", help="Output directory (default: current folder)")
    args = parser.parse_args()

    # ROI labels of interest
    ref_labels = [8, 47]  # Left & right cerebellum (reference region)
    target_labels = [
        1002, 1008, 1010, 1023, 1026, 1029, 1033,
        2002, 2008, 2010, 2015, 2023, 2029,
        1107, 2107
    ]

    aseg_img = nib.load(args.aseg)
    aseg_data = aseg_img.get_fdata().astype(int)

    # --- Reference VOI ---
    ref_mask = np.isin(aseg_data, ref_labels)
    ref_data = np.where(ref_mask, 1, 0)
    ref_img = nib.Nifti1Image(ref_data, affine=aseg_img.affine, header=aseg_img.header)
    nib.save(ref_img, os.path.join(args.outdir, "VOI_ref.nii.gz"))

    # --- Target VOI ---
    target_mask = np.isin(aseg_data, target_labels)
    target_data = np.where(target_mask, 1, 0)
    target_img = nib.Nifti1Image(target_data, affine=aseg_img.affine, header=aseg_img.header)
    nib.save(target_img, os.path.join(args.outdir, "VOI.nii.gz"))

    print("✅ Saved:")
    print(f"  • Reference VOI: {os.path.join(args.outdir, 'VOI_ref.nii.gz')}")
    print(f"  • Target VOI:    {os.path.join(args.outdir, 'VOI.nii.gz')}")

if __name__ == "__main__":
    main()
