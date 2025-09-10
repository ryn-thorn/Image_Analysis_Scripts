#!/usr/bin/env python3
"""
Full pipeline: Convert a complex MRS voxel NIfTI to a T1-aligned mask.

Usage:
    python MRS_T1_Mask.py <mrs_complex_nifti> <t1_nifti> <output_mask>
"""

import sys
import nibabel as nib
import numpy as np
import subprocess
import shutil

def complex_to_float_magnitude(mrs_file):
    """Convert DT=1792 complex NIfTI to float magnitude in memory."""
    img = nib.load(mrs_file)
    data = img.get_fdata(dtype=np.complex128)
    mag = np.abs(data)
    return mag, img

def create_t1_mask(mag_data, mrs_img, t1_img):
    """Project the MRS voxel onto T1 space as a binary mask."""
    t1_data = np.zeros(t1_img.shape, dtype=np.uint8)
    t1_affine = t1_img.affine
    t1_voxel_size = np.array(t1_img.header.get_zooms())
    mrs_voxel_size = np.array(mrs_img.header.get_zooms()[:3])

    # Compute MRS voxel center in world coordinates
    mrs_origin_mm = nib.affines.apply_affine(mrs_img.affine, [0, 0, 0])
    mrs_center_mm = mrs_origin_mm + mrs_voxel_size / 2

    # Compute half-width in T1 voxels
    half_width_vox = np.ceil((mrs_voxel_size / 2) / t1_voxel_size).astype(int)

    # Convert center to T1 voxel coordinates
    t1_center_vox = np.round(np.linalg.inv(t1_affine) @ np.append(mrs_center_mm, 1))[:3].astype(int)

    # Compute voxel ranges and clip to T1 bounds
    x0, y0, z0 = np.maximum(t1_center_vox - half_width_vox, 0)
    x1, y1, z1 = np.minimum(t1_center_vox + half_width_vox + 1, t1_data.shape)

    # Fill mask
    t1_data[x0:x1, y0:y1, z0:z1] = 1

    # Save mask as .nii.gz
    temp_output = "temp_mask.nii.gz"
    mask_img = nib.Nifti1Image(t1_data, t1_affine)
    mask_img.set_data_dtype(np.uint8)

    # Set header fields for FSLeyes
    mask_img.header['cal_min'] = t1_data.min()
    mask_img.header['cal_max'] = t1_data.max()
    mask_img.header.set_xyzt_units('mm', 'sec')
    mask_img.header['descrip'] = b''

    # Safe sform/qform handling
    sform = t1_img.get_sform()
    if sform is None:
        sform = np.eye(4)
    qform = t1_img.get_qform()
    if qform is None:
        qform = np.eye(4)

    mask_img.set_sform(sform, code=1)
    mask_img.set_qform(qform, code=1)

    nib.save(mask_img, temp_output)

    return temp_output

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)

    mrs_file = sys.argv[1]
    t1_file = sys.argv[2]
    output_mask = sys.argv[3]

    # Ensure output uses .nii.gz extension
    if not output_mask.endswith(".nii.gz"):
        output_mask += ".nii.gz"

    # Step 1: Convert complex -> float magnitude
    mag_data, mrs_img = complex_to_float_magnitude(mrs_file)

    # Step 2: Load T1
    t1_img = nib.load(t1_file)

    # Step 3: Create T1-aligned mask
    temp_mask_file = create_t1_mask(mag_data, mrs_img, t1_img)

    # Step 4: Move to desired output
    shutil.move(temp_mask_file, output_mask)
    print(f"T1-aligned MRS mask saved to: {output_mask}")

