#!/usr/bin/env python3
"""
Create a rotated MRS voxel mask in T1 space + PNG overlay check.

Example usage:
    ./MRS_T1_Mask.py \
        --t1 T1w.nii.gz \
        --mrs MRS_voxel.nii.gz \
        --out MRS_T1_mask.nii.gz
"""

import argparse
import numpy as np
import nibabel as nib
import matplotlib.pyplot as plt
import os

def create_mrs_mask(t1_file, mrs_file, out_file, tol=1e-6):
    # Load images
    t1 = nib.load(t1_file)
    t1_data = t1.get_fdata()
    t1_affine = t1.affine
    t1_shape = t1.shape

    mrs = nib.load(mrs_file)
    mrs_affine = mrs.affine

    # Precompute inverse affine: world -> MRS voxel indices
    inv_mrs_affine = np.linalg.inv(mrs_affine)

    # Define bounds in MRS index space (center origin)
    lo, hi = -0.5 - tol, 0.5 + tol

    # Build mask
    i, j, k = np.indices(t1_shape)
    nvox = i.size
    ijk = np.vstack([i.ravel(), j.ravel(), k.ravel(), np.ones(nvox)])

    world = t1_affine @ ijk
    mrs_idx = inv_mrs_affine @ world
    mrs_idx_xyz = mrs_idx[:3, :]

    inside_mask = (
        (mrs_idx_xyz[0, :] >= lo) & (mrs_idx_xyz[0, :] <= hi) &
        (mrs_idx_xyz[1, :] >= lo) & (mrs_idx_xyz[1, :] <= hi) &
        (mrs_idx_xyz[2, :] >= lo) & (mrs_idx_xyz[2, :] <= hi)
    )

    mask = inside_mask.reshape(t1_shape).astype(np.uint8)
    mask_img = nib.Nifti1Image(mask, t1_affine)
    nib.save(mask_img, out_file)

    print(f"[✓] Saved rotated MRS mask to: {out_file}")
    print(f"    Mask voxels (count): {int(mask.sum())}")

    # Make overlay PNG
    preview_file = os.path.splitext(out_file)[0] + "_overlay.png"
    mid_slices = [s // 2 for s in mask.shape]

    fig, axes = plt.subplots(1, 3, figsize=(12, 4))
    cmap_mask = plt.cm.get_cmap("autumn", 2)

    # Sagittal
    axes[0].imshow(np.rot90(t1_data[mid_slices[0], :, :]), cmap="gray")
    axes[0].imshow(np.rot90(mask[mid_slices[0], :, :]), cmap=cmap_mask, alpha=0.5)
    axes[0].set_title("Sagittal")

    # Coronal
    axes[1].imshow(np.rot90(t1_data[:, mid_slices[1], :]), cmap="gray")
    axes[1].imshow(np.rot90(mask[:, mid_slices[1], :]), cmap=cmap_mask, alpha=0.5)
    axes[1].set_title("Coronal")

    # Axial
    axes[2].imshow(np.rot90(t1_data[:, :, mid_slices[2]]), cmap="gray")
    axes[2].imshow(np.rot90(mask[:, :, mid_slices[2]]), cmap=cmap_mask, alpha=0.5)
    axes[2].set_title("Axial")

    for ax in axes:
        ax.axis("off")

    plt.tight_layout()
    plt.savefig(preview_file, dpi=150)
    plt.close()
    print(f"[✓] Preview overlay saved to: {preview_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Create rotated MRS voxel mask in T1 space (center origin)."
    )
    parser.add_argument("--t1", required=True, help="Path to T1 NIfTI image")
    parser.add_argument("--mrs", required=True, help="Path to MRS reference NIfTI")
    parser.add_argument("--out", required=True, help="Output mask NIfTI filename")

    args = parser.parse_args()
    create_mrs_mask(args.t1, args.mrs, args.out)
