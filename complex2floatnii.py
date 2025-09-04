#!/usr/bin/env python3
"""
Convert complex NIfTI images (DT=1792 / COMPLEX128) into real-valued
magnitude images (FLOAT32) that can be used in FSL.

Usage:
    python convert_complex_to_float.py input.nii output.nii
"""

import sys
import nibabel as nib
import numpy as np

def convert_complex_to_float(input_file, output_file):
    # Load the input image
    img = nib.load(input_file)

    # Force nibabel to interpret voxels as complex128
    data = img.get_fdata(dtype=np.complex128)

    # Compute magnitude
    mag = np.abs(data)

    # Make a new NIfTI image with same orientation/affine
    out_img = nib.Nifti1Image(mag.astype(np.float32), img.affine, img.header)

    # Explicitly set header datatype to FLOAT32
    out_img.header.set_data_dtype(np.float32)

    # Save
    nib.save(out_img, output_file)
    print(f"Saved FLOAT32 magnitude image to: {output_file}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python convert_complex_to_float.py input.nii output.nii")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    convert_complex_to_float(input_file, output_file)
