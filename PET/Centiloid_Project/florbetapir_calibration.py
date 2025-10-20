#!/usr/bin/env python3
"""
Centiloid calibration script for Florbetapir (FBP, 18F-AV45)
using the GAAIN paired PiB+FBP dataset and AVID VOIs.

Now includes:
- Automatic reorientation to standard space (fixes matrix inverse errors)
- Skipping of completed steps if outputs already exist

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


def safe_run_cmd(cmd, outfile=None):
    """Run shell command unless output already exists."""
    if outfile and os.path.exists(outfile) and os.path.getsize(outfile) > 0:
        print(f"✅ Skipping step: {os.path.basename(outfile)} already exists.")
        return
    print("CMD:", " ".join(cmd))
    try:
        subprocess.check_call(cmd)
    except subprocess.CalledProcessError as e:
        print(f"❌ Command failed: {' '.join(cmd)}\n{e}")
        raise


def merge_target_vois(target_dir, out_mask):
    """Merge all target VOIs in a folder into one mask."""
    voi_list = sorted(glob.glob(os.path.join(target_dir, "*.nii*")))
    if not voi_list:
        raise FileNotFoundError(f"No VOIs found in {target_dir}")

    print(f"🧩 Merging {len(voi_list)} target VOIs into one composite mask")
    tmp = voi_list[0]
    for voi in voi_list[1:]:
        safe_run_cmd(['fslmaths', tmp, '-add', voi, tmp])
    safe_run_cmd(['fslmaths', tmp, '-bin', out_mask], out_mask)
    return out_mask


def extract_mean_in_mask(img, mask):
    """Compute mean uptake in mask using fslstats."""
    try:
        out = subprocess.check_output(['fslstats', img, '-k', mask, '-M'])
        return float(out.decode().strip())
    except subprocess.CalledProcessError:
        return np.nan


def reorient_and_register(pet_img, t1_img, subj_out_dir, pet_prefix):
    """Reorient PET/T1 to std and register PET→T1."""
    os.makedirs(subj_out_dir, exist_ok=True)

    # Paths
    pet_reor = os.path.join(subj_out_dir, f"{pet_prefix}_reor.nii.gz")
    t1_reor = os.path.join(subj_out_dir, "T1_reor.nii.gz")
    pet_std = os.path.join(subj_out_dir, f"{pet_prefix}_pet_std.nii.gz")
    pet_t1 = os.path.join(subj_out_dir, f"{pet_prefix}_pet_t1.nii.gz")
    pet_t1_thr = os.path.join(subj_out_dir, f"{pet_prefix}_pet_t1_thr.nii.gz")
    pet_t1_reslice = os.path.join(subj_out_dir, f"{pet_prefix}_pet_t1_reslice.nii.gz")

    # Step 1: Reorient both to standard
    safe_run_cmd(['fslreorient2std', pet_img, pet_reor], pet_reor)
    safe_run_cmd(['fslreorient2std', t1_img, t1_reor], t1_reor)

    # Step 2: Reorient PET to std orientation again (keep consistent naming)
    safe_run_cmd(['fslreorient2std', pet_reor, pet_std], pet_std)

    # Step 3: Linear registration PET→T1
    safe_run_cmd(['flirt', '-ref', t1_reor, '-in', pet_std, '-out', pet_t1, '-v'], pet_t1)

    # Step 4: Threshold PET (remove negatives)
    safe_run_cmd(['fslmaths', pet_t1, '-thr', '0', pet_t1_thr], pet_t1_thr)

    # Step 5: Reslice PET into final T1 space
    safe_run_cmd(['flirt', '-ref', t1_reor, '-in', pet_t1_thr, '-out', pet_t1_reslice, '-applyxfm'], pet_t1_reslice)

    return pet_t1_reslice


def main(args):
    os.makedirs(args.outdir, exist_ok=True)

    # Create merged cortex mask
    merged_ctx = os.path.join(args.outdir, "composite_ctx_mask.nii.gz")
    if not os.path.exists(merged_ctx):
        merge_target_vois(args.voi_targets, merged_ctx)
    else:
        print(f"✅ Using existing composite mask: {merged_ctx}")

    subj_dirs = sorted(glob.glob(os.path.join(args.root, "*")))
    rows = []

    for subj_path in subj_dirs:
        subj_id = os.path.basename(subj_path)
        print(f"\n=== Processing subject: {subj_id} ===")
        subj_out_dir = os.path.join(args.outdir, subj_id)
        os.makedirs(subj_out_dir, exist_ok=True)

        # Locate files
        fbp = glob.glob(os.path.join(subj_path, "**", "*FBP*.nii*"), recursive=True) + \
              glob.glob(os.path.join(subj_path, "**", "*AV45*.nii*"), recursive=True) + \
              glob.glob(os.path.join(subj_path, "**", "*florbetapir*.nii*"), recursive=True)
        pib = glob.glob(os.path.join(subj_path, "**", "*PiB*.nii*"), recursive=True)
        t1 = glob.glob(os.path.join(subj_path, "**", "*MRI*.nii*"), recursive=True) + \
             glob.glob(os.path.join(subj_path, "**", "*T1*.nii*"), recursive=True)

        if not fbp or not pib or not t1:
            print(f"⚠️  Missing files for {subj_id}. Skipping.")
            continue

        try:
            fbp_t1 = reorient_and_register(fbp[0], t1[0], subj_out_dir, "PET_FBP")
            pib_t1 = reorient_and_register(pib[0], t1[0], subj_out_dir, "PET_PIB")
        except Exception as e:
            print(f"❌ Registration failed for {subj_id}: {e}")
            continue

        # Extract ROI means
        fbp_ctx_mean = extract_mean_in_mask(fbp_t1, merged_ctx)
        fbp_ref_mean = extract_mean_in_mask(fbp_t1, args.voi_ref)
        pib_ctx_mean = extract_mean_in_mask(pib_t1, merged_ctx)
        pib_ref_mean = extract_mean_in_mask(pib_t1, args.voi_ref)

        fbp_suvr = fbp_ctx_mean / fbp_ref_mean if fbp_ref_mean > 0 else np.nan
        pib_suvr = pib_ctx_mean / pib_ref_mean if pib_ref_mean > 0 else np.nan

        rows.append({"subj": subj_id, "fbp_suvr": fbp_suvr, "pib_suvr": pib_suvr})

    # Save raw SUVR table
    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(args.outdir, "calibration_raw_suvr.csv"), index=False)

    df_good = df.dropna(subset=['fbp_suvr', 'pib_suvr'])
    if df_good.empty:
        print("❌ No valid SUVR pairs found.")
        return

    # Regression
    slope, intercept, r, p, se = linregress(df_good['fbp_suvr'], df_good['pib_suvr'])
    print(f"\n📈 Regression: PiB_calc = {slope:.4f} * FBP_SUVR + {intercept:.4f} (R²={r**2:.3f})")

    df_good['pib_calc'] = slope * df_good['fbp_suvr'] + intercept

    # YC/AD estimates
    yc_mask = df_good['subj'].str.contains("YC", case=False)
    ad_mask = df_good['subj'].str.contains("E", case=False)
    mean_pib_yc = df_good.loc[yc_mask, 'pib_suvr'].mean()
    mean_pib_ad = df_good.loc[ad_mask, 'pib_suvr'].mean()
    if np.isnan(mean_pib_yc) or np.isnan(mean_pib_ad):
        mean_pib_yc = df_good['pib_suvr'].quantile(0.1)
        mean_pib_ad = df_good['pib_suvr'].quantile(0.9)

    # Centiloid formula
    A = 100 * slope / (mean_pib_ad - mean_pib_yc)
    B = 100 * (intercept - mean_pib_yc) / (mean_pib_ad - mean_pib_yc)
    df_good['centiloid'] = A * df_good['fbp_suvr'] + B
    df_good.to_csv(os.path.join(args.outdir, "calibration_results.csv"), index=False)

    # Save formula
    formula_path = os.path.join(args.outdir, "centiloid_formula.txt")
    with open(formula_path, "w") as f:
        f.write("# Centiloid conversion formula (AVID VOIs)\n")
        f.write(f"# CL = A * FBP_SUVR + B\n")
        f.write(f"A = {A:.6f}\nB = {B:.6f}\n")
        f.write(f"# slope (PiB_calc) = {slope:.6f}, intercept = {intercept:.6f}\n")
        f.write(f"# PiB mean YC = {mean_pib_yc:.6f}, PiB mean AD = {mean_pib_ad:.6f}\n")

    print(f"\n✅ Saved Centiloid conversion formula to: {formula_path}")
    print(f"   CL = {A:.3f} × FBP_SUVR + {B:.3f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, help="Root folder containing GAAIN subjects")
    parser.add_argument("--outdir", required=True, help="Output directory for results")
    parser.add_argument("--voi_targets", required=True, help="Folder containing target VOIs")
    parser.add_argument("--voi_ref", required=True, help="Path to reference VOI mask (e.g., cere_all.nii.gz)")
    args = parser.parse_args()
    main(args)
