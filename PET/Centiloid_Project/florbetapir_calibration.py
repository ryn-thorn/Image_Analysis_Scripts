#!/usr/bin/env python3
"""
Centiloid calibration script for Florbetapir (FBP, 18F-AV45)
using the GAAIN paired PiB+FBP dataset and AVID VOIs.

Target regions are combined into a single composite cortex mask.

Usage:
    python centiloid_calibration_fbp.py \
        --root /path/to/GAAIN/FBP_project_root \
        --outdir /path/to/output_centiloid_fbp \
        --voi_targets /path/to/AVID_VOIs/Target\ Regions \
        --voi_ref /path/to/AVID_VOIs/Reference\ Region/cere_all.nii.gz
"""

import os
import glob
import subprocess
import argparse
import numpy as np
import pandas as pd
from scipy.stats import linregress

def run_cmd(cmd):
    """Run a command and print it."""
    print("CMD:", " ".join(cmd))
    subprocess.check_call(cmd)

def safe_run_cmd(cmd, outfile=None):
    """Run a command only if outfile does not exist."""
    if outfile and os.path.exists(outfile):
        print(f"✅ Skipping step: {os.path.basename(outfile)} already exists.")
        return
    run_cmd(cmd)

def truncate_4d_to_3d(img_path, out_path):
    """Truncate 4D PET to first volume if necessary."""
    import nibabel as nib
    img = nib.load(img_path)
    if len(img.shape) == 4:
        print(f"⚠️  {os.path.basename(img_path)} is 4D, truncating to first volume")
        img_3d = nib.Nifti1Image(img.dataobj[..., 0], img.affine, img.header)
        nib.save(img_3d, out_path)
    else:
        if img_path != out_path:
            run_cmd(['cp', img_path, out_path])

def merge_target_vois(target_dir, out_mask):
    """Merge all target VOIs in a folder into one mask."""
    voi_list = sorted(glob.glob(os.path.join(target_dir, "*.nii*")))
    if not voi_list:
        raise FileNotFoundError(f"No VOIs found in {target_dir}")

    print(f"🧩 Merging {len(voi_list)} target VOIs into one composite mask")
    tmp = voi_list[0]
    for voi in voi_list[1:]:
        run_cmd(['fslmaths', tmp, '-add', voi, tmp])
    run_cmd(['fslmaths', tmp, '-bin', out_mask])
    return out_mask

def resample_mask_to_pet(mask, pet_img, out_mask):
    """Resample a mask to the PET image space."""
    safe_run_cmd(['flirt', '-in', mask, '-ref', pet_img, '-out', out_mask, '-interp', 'nearestneighbour'], out_mask)
    return out_mask

def extract_mean_in_mask(img, mask):
    """Compute mean uptake in mask using fslstats."""
    try:
        out = subprocess.check_output(['fslstats', img, '-k', mask, '-M'])
        return float(out.decode().strip())
    except subprocess.CalledProcessError:
        return np.nan

def pet_registration(pet_img, t1_img, pet_std, pet_t1, pet_thr, pet_reslice):
    """Reorient, register PET to T1, and threshold."""
    # Reorient PET to std
    safe_run_cmd(['fslreorient2std', pet_img, pet_std], pet_std)

    # Truncate if 4D
    truncate_4d_to_3d(pet_std, pet_std)

    # Register PET to T1
    safe_run_cmd(['flirt', '-ref', t1_img, '-in', pet_std, '-out', pet_t1], pet_t1)

    # Threshold at 0
    safe_run_cmd(['fslmaths', pet_t1, '-thr', '0', pet_thr], pet_thr)

    # Reslice to T1 (ensure matching size)
    safe_run_cmd(['flirt', '-ref', t1_img, '-in', pet_thr, '-out', pet_reslice], pet_reslice)
    return pet_reslice

def main(args):
    os.makedirs(args.outdir, exist_ok=True)

    # Merge cortex mask once
    merged_ctx = os.path.join(args.outdir, "composite_ctx_mask.nii.gz")
    if not os.path.exists(merged_ctx):
        merge_target_vois(args.voi_targets, merged_ctx)

    subj_dirs = sorted(glob.glob(os.path.join(args.root, "*")))
    rows = []

    for subj_path in subj_dirs:
        subj_id = os.path.basename(subj_path)
        print(f"\n=== Processing subject: {subj_id} ===")

        subj_out_dir = os.path.join(args.outdir, subj_id)
        os.makedirs(subj_out_dir, exist_ok=True)

        # Find files
        fbp = glob.glob(os.path.join(subj_path, "**", "*FBP*.nii*"), recursive=True) + \
              glob.glob(os.path.join(subj_path, "**", "*AV45*.nii*"), recursive=True) + \
              glob.glob(os.path.join(subj_path, "**", "*florbetapir*.nii*"), recursive=True)
        pib = glob.glob(os.path.join(subj_path, "**", "*PiB*.nii*"), recursive=True)
        t1 = glob.glob(os.path.join(subj_path, "**", "*MRI*.nii*"), recursive=True) + \
             glob.glob(os.path.join(subj_path, "**", "*T1*.nii*"), recursive=True) + \
             glob.glob(os.path.join(subj_path, "**", "*mri*.nii*"), recursive=True)

        if not fbp or not pib or not t1:
            print(f"⚠️  Missing files for {subj_id}. Skipping.")
            continue

        # Prepare file paths
        fbp_reor = os.path.join(subj_out_dir, "PET_FBP_reor.nii.gz")
        pib_reor = os.path.join(subj_out_dir, "PET_PIB_reor.nii.gz")
        t1_reor = os.path.join(subj_out_dir, "T1_reor.nii.gz")

        fbp_std = os.path.join(subj_out_dir, "PET_FBP_pet_std.nii.gz")
        fbp_t1 = os.path.join(subj_out_dir, "PET_FBP_pet_t1.nii.gz")
        fbp_thr = os.path.join(subj_out_dir, "PET_FBP_pet_t1_thr.nii.gz")
        fbp_reslice = os.path.join(subj_out_dir, "PET_FBP_pet_t1_reslice.nii.gz")

        pib_std = os.path.join(subj_out_dir, "PET_PIB_pet_std.nii.gz")
        pib_t1 = os.path.join(subj_out_dir, "PET_PIB_pet_t1.nii.gz")
        pib_thr = os.path.join(subj_out_dir, "PET_PIB_pet_t1_thr.nii.gz")
        pib_reslice = os.path.join(subj_out_dir, "PET_PIB_pet_t1_reslice.nii.gz")

        # Reorient
        safe_run_cmd(['fslreorient2std', fbp[0], fbp_reor], fbp_reor)
        safe_run_cmd(['fslreorient2std', pib[0], pib_reor], pib_reor)
        safe_run_cmd(['fslreorient2std', t1[0], t1_reor], t1_reor)

        # Register PETs
        fbp_pet_reslice = pet_registration(fbp_reor, t1_reor, fbp_std, fbp_t1, fbp_thr, fbp_reslice)
        pib_pet_reslice = pet_registration(pib_reor, t1_reor, pib_std, pib_t1, pib_thr, pib_reslice)

        # Resample masks to PET
        merged_ctx_res = resample_mask_to_pet(merged_ctx, fbp_pet_reslice,
                                             os.path.join(subj_out_dir, "merged_ctx_mask_reslice.nii.gz"))
        voi_ref_res = resample_mask_to_pet(args.voi_ref, fbp_pet_reslice,
                                          os.path.join(subj_out_dir, "voi_ref_reslice.nii.gz"))

        # Compute ROI means
        fbp_ctx_mean = extract_mean_in_mask(fbp_pet_reslice, merged_ctx_res)
        fbp_ref_mean = extract_mean_in_mask(fbp_pet_reslice, voi_ref_res)
        pib_ctx_mean = extract_mean_in_mask(pib_pet_reslice, merged_ctx_res)
        pib_ref_mean = extract_mean_in_mask(pib_pet_reslice, voi_ref_res)

        fbp_suvr = fbp_ctx_mean / fbp_ref_mean if fbp_ref_mean > 0 else np.nan
        pib_suvr = pib_ctx_mean / pib_ref_mean if pib_ref_mean > 0 else np.nan

        rows.append({
            "subj": subj_id,
            "fbp_suvr": fbp_suvr,
            "pib_suvr": pib_suvr
        })

    # Save raw SUVRs
    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(args.outdir, "calibration_raw_suvr.csv"), index=False)

    df_good = df.dropna(subset=['fbp_suvr', 'pib_suvr'])
    if df_good.empty:
        print("❌ No valid SUVR pairs found.")
        return

    # Linear regression
    slope, intercept, r, p, se = linregress(df_good['fbp_suvr'], df_good['pib_suvr'])
    print(f"\n📈 Regression: PiB_calc = {slope:.4f} * FBP_SUVR + {intercept:.4f} (R²={r**2:.3f})")

    df_good['pib_calc'] = slope * df_good['fbp_suvr'] + intercept

    # Estimate YC/AD means
    yc_mask = df_good['subj'].str.contains("YC", case=False)
    ad_mask = df_good['subj'].str.contains("E", case=False)

    mean_pib_yc = df_good.loc[yc_mask, 'pib_suvr'].mean()
    mean_pib_ad = df_good.loc[ad_mask, 'pib_suvr'].mean()
    if np.isnan(mean_pib_yc) or np.isnan(mean_pib_ad):
        mean_pib_yc = df_good['pib_suvr'].quantile(0.1)
        mean_pib_ad = df_good['pib_suvr'].quantile(0.9)

    # Centiloid formula coefficients
    A = 100 * slope / (mean_pib_ad - mean_pib_yc)
    B = 100 * (intercept - mean_pib_yc) / (mean_pib_ad - mean_pib_yc)

    df_good['centiloid'] = A * df_good['fbp_suvr'] + B
    df_good.to_csv(os.path.join(args.outdir, "calibration_results.csv"), index=False)

    # Save formula
    formula_path = os.path.join(args.outdir, "centiloid_formula.txt")
    with open(formula_path, "w") as f:
        f.write("# Centiloid conversion formula (AVID VOIs)\n")
        f.write(f"# CL = A * FBP_SUVR + B\n")
        f.write(f"A = {A:.6f}\n")
        f.write(f"B = {B:.6f}\n")
        f.write(f"# slope (PiB_calc) = {slope:.6f}, intercept = {intercept:.6f}\n")
        f.write(f"# PiB mean YC = {mean_pib_yc:.6f}, PiB mean AD = {mean_pib_ad:.6f}\n")

    print(f"\n✅ Saved Centiloid conversion formula to: {formula_path}")
    print(f"   CL = {A:.3f} × FBP_SUVR + {B:.3f}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, help="Root folder containing GAAIN subjects")
    parser.add_argument("--outdir", required=True, help="Output directory for results")
    parser.add_argument("--voi_targets", required=True, help="Folder containing target VOIs (multiple .nii.gz)")
    parser.add_argument("--voi_ref", required=True, help="Path to reference VOI mask (e.g., cere_all.nii.gz)")
    args = parser.parse_args()
    main(args)
