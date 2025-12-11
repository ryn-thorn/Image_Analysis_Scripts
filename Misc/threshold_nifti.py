#!/usr/local/bin/bash python
import nibabel as nib
import numpy as np
import sys

# Usage: python threshold_nifti.py input.nii.gz output_thr.nii.gz 0.2

input_file = sys.argv[1]
output_file = sys.argv[2]
threshold = float(sys.argv[3])

# Load image
img = nib.load(input_file)
data = img.get_fdata()  # ensures float64, avoids truncation issues

# Threshold
mask = (data <= threshold).astype(np.float32)  # or np.uint8 if you prefer

# Save as new NIfTI
out_img = nib.Nifti1Image(mask, img.affine, img.header)
nib.save(out_img, output_file)
print(f"Thresholded image saved to {output_file}")
