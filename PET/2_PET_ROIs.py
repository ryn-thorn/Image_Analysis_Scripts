import os
import os.path as op
import glob as glob
from shutil import copyfile
import subprocess
from itertools import compress

petDir = '/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv/mSUVr_2025'
fsDir = '/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/freesurfer/freesurfer_6.0/03_Analysis'
roi_target = '/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv/mSUVr_2025/target_rois.txt'

paths_pet = sorted(glob.glob(op.join(petDir, 'IAM_*')))
paths_fs = sorted(glob.glob(op.join(fsDir, 'IAM_*')))
paths_out = []

# Find subjects that have both PET and FS Segmentations
subs_pet = [op.basename(x) for x in paths_pet]
subs_fs = [op.basename(x) for x in paths_fs]
idx = [x in subs_fs for x in subs_pet]
subs_pet = list(compress(subs_pet, idx))
idx = [x in subs_pet for x in subs_fs]
subs_fs = list(compress(subs_fs, idx))
paths_pet = sorted([op.join(petDir, x) for x in subs_pet])
paths_fs = sorted([op.join(fsDir, x) for x in subs_fs])
failedRun = []
for idx, (path_pet, path_fs) in enumerate(zip(paths_pet, paths_fs)):
    sub = op.basename(path_pet)
    roiDir = op.join(path_pet, 'roi')
    os.makedirs(roiDir, exist_ok=True)
    arg = ['fsmakeroi', '-o', roiDir, op.join(path_fs, 'mri', 'aparc+aseg.mgz'), roi_target]
    completion = subprocess.run(arg)
    if completion.returncode != 0:
        failedRun.append(sub)