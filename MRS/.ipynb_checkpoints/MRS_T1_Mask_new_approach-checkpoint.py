#!/usr/bin/env python3
#######
#
#
# Note to self: this script produces an MRS mask that is very close but lacks sagittal 
# tilt seen in the MRS acquisition png.
#
#
#######
"""
Convert an MRS voxel NIfTI (1x1x1 spectroscopy file) into a binary mask aligned to a T1 image.
"""

import nibabel as nib
import numpy as np

# -----------------------------
# Input files
# -----------------------------
t1_file = "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/mrs/04_pc_voxel_segmentation/1002/T1.nii.gz"
mrs_file = "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/mrs/04_pc_voxel_segmentation/1002/PC_PRESS.nii.gz"   # the spectroscopy voxel .nii

# -----------------------------
# Load data
# -----------------------------
t1_img = nib.load(t1_file)
t1_affine = t1_img.affine
t1_shape = t1_img.shape
t1_hdr = t1_img.header
t1_zooms = t1_hdr.get_zooms()[:3]

mrs_img = nib.load(mrs_file)
mrs_affine = mrs_img.affine
mrs_hdr = mrs_img.header
mrs_zooms = mrs_hdr.get_zooms()[:3]  # should be ~20x20x20 mm

# -----------------------------
# Find the voxel center in world coordinates
# -----------------------------
# The single voxel of the MRS image is at index (0,0,0)
voxel_index = np.array([0.5,0.5,0.5,1])
#voxel_index = np.array([0,0,0,1])
world_coords = mrs_affine @ voxel_index
center = world_coords[:3]

# Half-sizes in mm
half_sizes = np.array(mrs_zooms) / 2.0

# -----------------------------
# Build cube in T1 voxel space
# -----------------------------
mask = np.zeros(t1_shape, dtype=np.uint8)

# Get all T1 voxel coordinates
i, j, k = np.indices(t1_shape)
ijk = np.vstack([i.ravel(), j.ravel(), k.ravel(), np.ones(i.size)])

# Convert T1 voxel indices to world (scanner) space
world = t1_affine @ ijk
x, y, z = world[:3]

# Fill cube condition: within half_sizes along each axis
inside = (
    (np.abs(x - center[0]) <= half_sizes[0]) &
    (np.abs(y - center[1]) <= half_sizes[1]) &
    (np.abs(z - center[2]) <= half_sizes[2])
)

mask.ravel()[inside] = 1
mask_img = nib.Nifti1Image(mask, t1_affine)

# -----------------------------
# Save output
# -----------------------------
out_file = "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/mrs/04_pc_voxel_segmentation/1002/MRS_mask_in_T1.nii.gz"
nib.save(mask_img, out_file)
print(f"Saved mask: {out_file}")
print(f"Mask voxels filled: {mask.sum()}")
