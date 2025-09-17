import nibabel as nib
import numpy as np

mrs = nib.load("/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/mrs/04_pc_voxel_segmentation/1002/PC_PRESS.nii.gz")
hdr = mrs.header

print("hdr.get_zooms()[:3] =", hdr.get_zooms()[:3])
print("sform:\n", hdr.get_sform(coded=True))
print("qform:\n", hdr.get_qform(coded=True))

# compute center using nibabel's .affine (which chooses sform if valid, else qform)
aff = mrs.affine
print("nib.load(...).affine:\n", aff)

# center using voxel index (0,0,0,1)
center0 = aff @ np.array([0,0,0,1])
center05 = aff @ np.array([0.5,0.5,0.5,1])
print("center at (0,0,0):", center0[:3])
print("center at (0.5,0.5,0.5):", center05[:3])
