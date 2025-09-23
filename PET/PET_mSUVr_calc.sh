import os
import os.path as op
import glob
import numpy as np
import pandas as pd
import nibabel as nib
import multiprocessing
from joblib import Parallel, delayed
from tqdm import tqdm
import matplotlib.pyplot as plt
import seaborn as sns

def vectorize(img, mask):
    """
    Returns vectorized image based on brain mask, requires no input
    parameters
    If the input is 1D or 2D, unpatch it to 3D or 4D using a mask
    If the input is 3D or 4D, vectorize it using a mask
    Classification: Function
    Parameters
    ----------
    img : ndarray
        1D, 2D, 3D or 4D image array to vectorize
    mask : ndarray
        3D image array for masking
    Returns
    -------
    vec : N X number_of_voxels vector or array, where N is the number
        of DWI volumes
    Examples
    --------
    vec = vectorize(img) if there's no mask
    vec = vectorize(img, mask) if there's a mask
    """
    if mask is None:
        mask = np.ones((img.shape[0],
                        img.shape[1],
                        img.shape[2]),
                       order='F')
    mask = mask.astype(bool)
    if img.ndim == 1:
        n = img.shape[0]
        s = np.zeros((mask.shape[0],
                      mask.shape[1],
                      mask.shape[2]),
                     order='F')
        s[mask] = img
    if img.ndim == 2:
        n = img.shape[0]
        s = np.zeros((mask.shape[0],
                      mask.shape[1],
                      mask.shape[2], n),
                     order='F')
        for i in range(0, n):
            s[mask, i] = img[i,:]
    if img.ndim == 3:
        maskind = np.ma.array(img, mask=np.logical_not(mask))
        s = np.ma.compressed(maskind)
    if img.ndim == 4:
        s = np.zeros((img.shape[-1], np.sum(mask).astype(int)), order='F')
        for i in range(0, img.shape[-1]):
            tmp = img[:,:,:,i]
            # Compressed returns non-masked area, so invert the mask first
            maskind = np.ma.array(tmp, mask=np.logical_not(mask))
            s[i,:] = np.ma.compressed(maskind)
    return np.squeeze(s)

def roimean(subDir):
    imgPath = op.join(subDir, 'SUV_reg.nii.gz')
    roiDir = op.join(subDir, 'roi')
    subMean = []
    subProc = []
    if op.exists(imgPath):
        subProc = op.basename(subDir)
        roiList = sorted(glob.glob(op.join(roiDir, '*.nii.gz*')))
        roiID = [op.basename(x).split('.nii.gz')[0] for x in roiList]
        img_obj = nib.load(imgPath)
        hdr = img_obj.header
        affine = img_obj.affine
        img = np.array(img_obj.dataobj)
        tqdm.write('Processing {}'.format(op.basename(subDir)))
        for j in roiList:
            tqdm.write('...computing {}'.format(op.basename(j).split('.nii.gz')[0]))
            roi = np.array(nib.load(j).dataobj, dtype=int)
            subMean.append(np.nanmean(vectorize(img, roi)))
    return subMean, subProc

mainDir = '/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv/mSUVr_2025'
redCap_FS = '/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv/mSUVr_2025/IAMDatabaseY0-FreeSurferNormalizat_DATA_2025-09-19_1637.csv'
outDir = mainDir

subjects = sorted(glob.glob(op.join(mainDir, '*')))
subID = [op.basename(x) for x in subjects]

inputs = tqdm(range(0, len(subjects)), desc='Computing Means')
data, subs = zip(*Parallel(n_jobs=16, prefer='processes')(delayed(roimean)(subjects[i]) for i in inputs))
# for i in inputs:
#     data, subs = roimean(subjects[i])
# for i in subID:
#     subDir = op.join(mainDir, i)
#     imgPath = op.join(subDir, 'SUV_REG.nii.gz')
#     if op.exists(imgPath):
#         roiDir = op.join(subDir, 'roi')
#         roiList = sorted(glob.glob(op.join(roiDir, '*.nii.gz*')))
#         roiID = [op.basename(x).split('.nii.gz')[0] for x in roiList]
#         img_obj = nib.load(imgPath)
#         hdr = img_obj.header
#         affine = img_obj.affine
#         img = np.array(img_obj.dataobj)
#         print('Processing {}'.format(i))
#         subMean = []
#         for j in roiList:
#             print('...computing {}'.format(op.basename(j).split('.nii.gz')[0]))
#             roi = np.array(nib.load(j).dataobj, dtype=int)
#             subMean.append(np.nanmean(vectorize(img, roi)))
#         data.append(subMean)

roiDir = op.join(subjects[0], 'roi')
roiList = sorted(glob.glob(op.join(roiDir, '*.nii.gz*')))
roiID = [op.basename(x).split('.nii.gz')[0] for x in roiList]
df = pd.DataFrame(data, columns=roiID, index=subs)
df.dropna(how='all', inplace=True)
df_ = pd.read_csv(redCap_FS, index_col=0)
age = []
sex = []
mta = []
amyloid = []
for index, row in df.iterrows():
    age.append(df_.loc[index]['age'])
    amyloid.append(df_.loc[index]['pet_amyloid'])
    if df_.loc[index]['sex'] == 1:
        sex.append('M')
    else:
        sex.append('F')
    mta.append(np.mean([df_.loc[index]['mta_l'], df_.loc[index]['mta_r']]))
df.insert(0, 'sex', sex)
df.insert(1, 'age', age)
df.insert(2, 'amyloid', amyloid)
df.insert(3, 'mta', mta)
df.loc[:, 'amyloid'] = df.loc[:, 'amyloid'].astype(int)
cerebellum_mean = np.nanmean(df.loc[: , 'Left-Cerebellum-Cortex':'Right-Cerebellum-Cortex'], axis=1)
# df.drop(labels=['ctx-rh-precuneus','ctx-lh-precuneus'], axis=1, inplace=True)
df.loc[:, 'ctx-lh-caudalanteriorcingulate':'ctx-rh-superiorparietal'] = df.loc[:, 'ctx-lh-caudalanteriorcingulate':'ctx-rh-superiorparietal'].mul(1/cerebellum_mean, axis=0)
df['mSUVr'] = df.loc[:, 'ctx-lh-caudalanteriorcingulate':'ctx-rh-superiorparietal'].mean(axis=1)
# df.drop(labels=['Left-Cerebellum-Cortex','Right-Cerebellum-Cortex'], axis=1, inplace=True)
df.to_csv(op.join(outDir, 'mSUVR_Values.csv'))

rc = pd.DataFrame(data, columns=roiID, index=subs)
rc.dropna(how='all', inplace=True)
rc['mSUVr'] = df['mSUVr']
rc.index.name = 'studyid'
rc.to_csv(op.join(outDir, 'Raw_SUV_Values.csv'))

df.columns

mean =  np.mean(df.loc[:, ['mean']], axis=1)
sns.set_context('talk')
sns.set_style('darkgrid')
fig = plt.figure(figsize=(12, 8), dpi=150, facecolor='w', edgecolor='k')
s = sns.scatterplot(data=df, x='age', y=mean, hue=df.amyloid.to_list(), size=df.mta.to_list())
plt.legend(['Amyloid (+)', 'Amyloid (-)'], title='Amyloid Rating')
plt.xlabel('Age')
plt.ylabel('mSUVr')
ax = s.axes
ax.axhline(1.17, c = 'r', ls='--')
ax.axhline(1.0, c = 'r', ls='--')
plt.title('mSUVr vs Age')
plt.savefig(op.join(outDir, 'mSUVr_vs_Age.jpg'), dpi=150)

print('Total sample size: {}'.format(df.loc[:, 'mean'].count()))
print('Sample size with mSUVr < 1.17: {}'.format(df.loc[df.loc[:, 'mean'] < 1.17, 'mean'].count()))
print('Sample size with mSUVr >= 1.17: {}'.format(df.loc[df.loc[:, 'mean'] >= 1.17, 'mean'].count()))
print('Sample tertile is:')
pd.qcut(df['mean'], 3, labels=None)
