import os
import os.path as op
import glob
import numpy as np
import pandas as pd
import nibabel as nib
from joblib import Parallel, delayed
from tqdm import tqdm
import matplotlib.pyplot as plt
import seaborn as sns


def vectorize(img, mask):
    """Vectorize image using a mask."""
    if mask is None:
        mask = np.ones(img.shape[:3], order='F')
    mask = mask.astype(bool)

    if img.ndim == 1:
        s = np.zeros(mask.shape, order='F')
        s[mask] = img
    elif img.ndim == 2:
        s = np.zeros(mask.shape + (img.shape[0],), order='F')
        for i in range(img.shape[0]):
            s[mask, i] = img[i, :]
    elif img.ndim == 3:
        maskind = np.ma.array(img, mask=~mask)
        s = np.ma.compressed(maskind)
    elif img.ndim == 4:
        s = np.zeros((img.shape[-1], mask.sum()), order='F')
        for i in range(img.shape[-1]):
            tmp = img[..., i]
            maskind = np.ma.array(tmp, mask=~mask)
            s[i, :] = np.ma.compressed(maskind)
    else:
        raise ValueError(f"Unsupported image ndim={img.ndim}")
    return np.squeeze(s)


def roimean(subDir):
    """Compute mean PET values inside ROI masks."""
    imgPath = op.join(subDir, 'SUV_REG_reslice.nii.gz')
    subProc = op.basename(subDir)

    if not op.exists(imgPath):
        tqdm.write(f"Skipping {subProc}: PET file not found")
        return None

    roiDir = op.join(subDir, 'roi')
    roiList = sorted(glob.glob(op.join(roiDir, '*.nii.gz*')))
    if len(roiList) == 0:
        tqdm.write(f"Skipping {subProc}: no ROI masks found in {roiDir}")
        return None

    try:
        img_obj = nib.load(imgPath)
        img = np.array(img_obj.dataobj)
    except Exception as e:
        tqdm.write(f"Skipping {subProc}: error loading PET ({e})")
        return None

    subMean = []
    tqdm.write(f"Processing {subProc}")
    for j in roiList:
        roi_name = op.basename(j).split('.nii.gz')[0]
        tqdm.write(f"...computing {roi_name}")
        roi = np.array(nib.load(j).dataobj, dtype=int)
        if roi.sum() == 0:
            subMean.append(np.nan)
        else:
            subMean.append(np.nanmean(vectorize(img, roi)))

    return subMean, subProc


# --- Paths ---
mainDir = '/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/pet_suv/florbetaben'
redCap_FS = '/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/pet_suv/IAMDatabaseY0-FreeSurferNormalizat_DATA_2025-12-15_1244.csv'
outDir = mainDir

subjects = sorted(glob.glob(op.join(mainDir, 'sub-*')))
subID = [op.basename(x) for x in subjects]

# --- Parallel ROI means ---
inputs = range(len(subjects))
results = Parallel(n_jobs=16, prefer='processes')(
    delayed(roimean)(subjects[i]) for i in tqdm(inputs, desc='Computing Means')
)
results = [r for r in results if r is not None]  # drop failed cases

if len(results) == 0:
    raise RuntimeError("No subjects were processed successfully!")

data, subs = zip(*results)

# --- Build dataframe ---
roiDir = op.join(subjects[0], 'roi')
roiList = sorted(glob.glob(op.join(roiDir, '*.nii.gz*')))
roiID = [op.basename(x).split('.nii.gz')[0] for x in roiList]

df = pd.DataFrame(data, columns=roiID, index=subs)
df.dropna(how='all', inplace=True)

df_ = pd.read_csv(redCap_FS, index_col=0)
age, sex, mta, amyloid = [], [], [], []

for index in df.index:
    age.append(df_.loc[index]['age'])
    amyloid.append(df_.loc[index]['pet_amyloid'])
    sex.append('M' if df_.loc[index]['sex'] == 1 else 'F')
    mta.append(np.mean([df_.loc[index]['mta_l'], df_.loc[index]['mta_r']]))

df.insert(0, 'sex', sex)
df.insert(1, 'age', age)
df.insert(2, 'amyloid', amyloid)
df.insert(3, 'mta', mta)
# Convert amyloid column to nullable integer (keeps missing values as <NA>)
df['amyloid'] = df['amyloid'].astype('Int64')

# Quick diagnostic: how many amyloid values are missing?
missing_count = df['amyloid'].isna().sum()
print(f"\n[INFO] Amyloid column converted to Int64. Missing values: {missing_count}\n")

# --- Compute SUVr ---
cerebellum_mean = np.nanmean(df.loc[:, 'Left-Cerebellum-Cortex':'Right-Cerebellum-Cortex'], axis=1)
df.loc[:, 'ctx-lh-caudalanteriorcingulate':'ctx-rh-superiorparietal'] = \
    df.loc[:, 'ctx-lh-caudalanteriorcingulate':'ctx-rh-superiorparietal'].div(cerebellum_mean, axis=0)
df['mSUVr'] = df.loc[:, 'ctx-lh-caudalanteriorcingulate':'ctx-rh-superiorparietal'].mean(axis=1)

# --- Save outputs ---
df.to_csv(op.join(outDir, 'mSUVR_Values.csv'))
rc = pd.DataFrame(data, columns=roiID, index=subs)
rc.dropna(how='all', inplace=True)
rc['mSUVr'] = df['mSUVr']
rc.index.name = 'studyid'
rc.to_csv(op.join(outDir, 'Raw_SUV_Values.csv'))

# --- Plot ---
sns.set_context('talk')
sns.set_style('darkgrid')
fig = plt.figure(figsize=(12, 8), dpi=150)
s = sns.scatterplot(data=df, x='age', y='mSUVr', hue='amyloid', size='mta')
plt.xlabel('Age')
plt.ylabel('mSUVr')
plt.legend(title='Amyloid Rating')
ax = s.axes
ax.axhline(1.17, c='r', ls='--')
ax.axhline(1.0, c='r', ls='--')
plt.title('mSUVr vs Age')
plt.savefig(op.join(outDir, 'mSUVr_vs_Age.jpg'), dpi=150)

print(f"Total sample size: {df['mSUVr'].count()}")
print(f"Sample size with mSUVr < 1.17: {df.loc[df['mSUVr'] < 1.17, 'mSUVr'].count()}")
print(f"Sample size with mSUVr >= 1.17: {df.loc[df['mSUVr'] >= 1.17, 'mSUVr'].count()}")
print("Sample tertile is:")
print(pd.qcut(df['mSUVr'], 3, labels=None))
