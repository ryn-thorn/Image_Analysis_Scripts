#!/usr/bin/env python3
"""
Centiloid calibration script for FBB using the GAAIN paired PiB+FBB dataset.
Adapted to the user's PET->T1 registration steps (FSL-based).

Usage:
    python centiloid_calibration_fbb.py \
        --root /path/to/GAAIN/FBB_project_root \
        --outdir /path/to/output_centiloid \
        --voi_ctx /path/to/CTX_target_mask.nii.gz \
        --voi_wc /path/to/WholeCerebellum_ref_mask.nii.gz

Requirements:
    - FSL in PATH (fslreorient2std, flirt, fslmaths, fslstats)
    - Python 3 with numpy, pandas, scipy
"""
import os
import glob
import subprocess
import argparse
import numpy as np
import pandas as pd
from scipy.stats import linregress

def run_cmd(cmd):
    print("CMD:", " ".join(cmd))
    subprocess.check_call(cmd)


def reorient_and_register(pet_img, t1_img, subj_out_dir, pet_prefix):
    """Reorient PET to std and register to T1 using user’s method."""
    os.makedirs(subj_out_dir, exist_ok=True)

    pet_std = os.path.join(subj_out_dir, f"{pet_prefix}_pet_std.nii.gz")
    pet_t1 = os.path.join(subj_out_dir, f"{pet_prefix}_pet_t1.nii.gz")
    pet_t1_thr = os.path.join(subj_out_dir, f"{pet_prefix}_pet_t1_thr.nii.gz")
    pet_t1_reslice = os.path.join(subj_out_dir, f"{pet_prefix}_pet_t1_reslice.nii.gz")

    run_cmd(['fslreorient2std', pet_img, pet_std])
    run_cmd(['flirt', '-ref', t1_img, '-in', pet_std, '-out', pet_t1, '-v'])
    run_cmd(['fslmaths', pet_t1, '-thr', '0', pet_t1_thr])
    run_cmd(['flirt', '-ref', t1_img, '-in', pet_t1_thr, '-out', pet_t1_reslice])

    return pet_t1_reslice


def extract_mean_in_mask(img, mask):
    """Compute mean uptake in mask using fslstats."""
    try:
        out = subprocess.check_output(['fslstats', img, '-k', mask, '-M'])
        return float(out.decode().strip())
    except subprocess.CalledProcessError:
        return np.nan


def main(args):
    os.makedirs(args.outdir, exist_ok=True)

    subj_dirs = sorted(glob.glob(os.path.join(args.root, "*")))
    rows = []

    for subj_path in subj_dirs:
        subj_id = os.path.basename(subj_path)
        print(f"\n=== Processing subject: {subj_id} ===")

        # Create a dedicated output folder for this subject
        subj_out_dir = os.path.join(args.outdir, subj_id)
        os.makedirs(subj_out_dir, exist_ok=True)

        fbb = glob.glob(os.path.join(subj_path, "**", "*FBB*.nii*"), recursive=True)
        pib = glob.glob(os.path.join(subj_path, "**", "*PIB*.nii*"), recursive=True)
        t1 = glob.glob(os.path.join(subj_path, "**", "*MR*.nii*"), recursive=True) + \
             glob.glob(os.path.join(subj_path, "**", "*t1*.nii*"), recursive=True)

        if not fbb or not pib or not t1:
            print(f"⚠️  Missing files for {subj_id}. Skipping.")
            continue

        fbb_t1 = reorient_and_register(fbb[0], t1[0], subj_out_dir, "PET_FBB")
        pib_t1 = reorient_and_register(pib[0], t1[0], subj_out_dir, "PET_PIB")

        # ROI means
        fbb_ctx_mean = extract_mean_in_mask(fbb_t1, args.voi_ctx)
        fbb_ref_mean = extract_mean_in_mask(fbb_t1, args.voi_wc)
        pib_ctx_mean = extract_mean_in_mask(pib_t1, args.voi_ctx)
        pib_ref_mean = extract_mean_in_mask(pib_t1, args.voi_wc)

        fbb_suvr = fbb_ctx_mean / fbb_ref_mean if fbb_ref_mean > 0 else np.nan
        pib_suvr = pib_ctx_mean / pib_ref_mean if pib_ref_mean > 0 else np.nan

        rows.append({
            "subj": subj_id,
            "fbb_suvr": fbb_suvr,
            "pib_suvr": pib_suvr
        })

    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(args.outdir, "calibration_raw_suvr.csv"), index=False)

    df_good = df.dropna(subset=['fbb_suvr', 'pib_suvr'])
    if df_good.empty:
        print("❌ No valid SUVR pairs found.")
        return

    # Linear regression
    slope, intercept, r, p, se = linregress(df_good['fbb_suvr'], df_good['pib_suvr'])
    print(f"\n📈 Regression: PiB_calc = {slope:.4f} * FBB_SUVR + {intercept:.4f} (R²={r**2:.3f})")

    df_good['pib_calc'] = slope * df_good['fbb_suvr'] + intercept

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

    df_good['centiloid'] = A * df_good['fbb_suvr'] + B
    df_good.to_csv(os.path.join(args.outdir, "calibration_results.csv"), index=False)

    # Save formula
    formula_path = os.path.join(args.outdir, "centiloid_formula.txt")
    with open(formula_path, "w") as f:
        f.write("# Centiloid conversion formula (for this pipeline)\n")
        f.write(f"# CL = A * FBB_SUVR + B\n")
        f.write(f"A = {A:.6f}\n")
        f.write(f"B = {B:.6f}\n")
        f.write(f"# slope (PiB_calc) = {slope:.6f}, intercept = {intercept:.6f}\n")
        f.write(f"# PiB mean YC = {mean_pib_yc:.6f}, PiB mean AD = {mean_pib_ad:.6f}\n")

    print(f"\n✅ Saved Centiloid conversion formula to: {formula_path}")
    print(f"   CL = {A:.3f} × FBB_SUVR + {B:.3f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, help="Root folder containing GAAIN subjects")
    parser.add_argument("--outdir", required=True, help="Output directory for results")
    parser.add_argument("--voi_ctx", required=True, help="Path to cortical target VOI mask")
    parser.add_argument("--voi_wc", required=True, help="Path to whole cerebellum VOI mask")
    args = parser.parse_args()
    main(args)
