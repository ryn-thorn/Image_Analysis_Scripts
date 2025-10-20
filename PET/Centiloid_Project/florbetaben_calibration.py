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
import nibabel as nib


# ================================
# Utility functions
# ================================
def run_cmd(cmd):
    """Run shell command with logging."""
    print("CMD:", " ".join(cmd))
    subprocess.check_call(cmd)


def safe_run_cmd(cmd, output_file):
    """Run command only if output file does not already exist."""
    if os.path.exists(output_file) and os.path.getsize(output_file) > 0:
        print(f"✅ Skipping step: {os.path.basename(output_file)} already exists.")
    else:
        run_cmd(cmd)


# ================================
# Core processing steps
# ================================
def reorient_and_register(pet_img, t1_img, subj_out_dir, pet_prefix):
    """Reorient PET to std and register directly to T1. Skip threshold/reslice."""
    os.makedirs(subj_out_dir, exist_ok=True)

    pet_std = os.path.join(subj_out_dir, f"{pet_prefix}_pet_std.nii.gz")
    pet_t1 = os.path.join(subj_out_dir, f"{pet_prefix}_pet_t1.nii.gz")

    # Reorient and register
    safe_run_cmd(['fslreorient2std', pet_img, pet_std], pet_std)
    safe_run_cmd(['flirt', '-ref', t1_img, '-in', pet_std, '-out', pet_t1, '-v'], pet_t1)

    return pet_t1


def transform_mask_to_t1(mask_path, t1_img, subj_out_dir, prefix):
    """Resample VOI mask into subject T1 space using flirt applyxfm."""
    mask_t1 = os.path.join(subj_out_dir, f"{prefix}_mask_t1.nii.gz")
    safe_run_cmd([
        'flirt',
        '-ref', t1_img,
        '-in', mask_path,
        '-out', mask_t1,
        '-applyxfm',
        '-usesqform'
    ], mask_t1)
    return mask_t1


def extract_mean_in_mask(img, mask):
    """Compute mean uptake in mask using fslstats."""
    try:
        out = subprocess.check_output(['fslstats', img, '-k', mask, '-M'])
        return float(out.decode().strip())
    except subprocess.CalledProcessError:
        return np.nan


def check_same_grid(img1, img2):
    """Return True if img1 and img2 have same grid size and voxel size."""
    a = nib.load(img1)
    b = nib.load(img2)
    return a.shape == b.shape and np.allclose(a.header.get_zooms(), b.header.get_zooms(), atol=1e-3)


# ================================
# Main analysis
# ================================
def main(args):
    os.makedirs(args.outdir, exist_ok=True)

    subj_dirs = sorted(glob.glob(os.path.join(args.root, "*")))
    rows = []

    for subj_path in subj_dirs:
        subj_id = os.path.basename(subj_path)
        print(f"\n=== Processing subject: {subj_id} ===")

        subj_out_dir = os.path.join(args.outdir, subj_id)
        os.makedirs(subj_out_dir, exist_ok=True)

        # Locate files
        fbb = glob.glob(os.path.join(subj_path, "**", "*FBB*.nii*"), recursive=True)
        pib = glob.glob(os.path.join(subj_path, "**", "*PIB*.nii*"), recursive=True)
        t1 = glob.glob(os.path.join(subj_path, "**", "*MR*.nii*"), recursive=True) + \
             glob.glob(os.path.join(subj_path, "**", "*t1*.nii*"), recursive=True)

        if not fbb or not pib or not t1:
            print(f"⚠️  Missing files for {subj_id}. Skipping.")
            continue

        # Registration (T1 space)
        fbb_t1 = reorient_and_register(fbb[0], t1[0], subj_out_dir, "PET_FBB")
        pib_t1 = reorient_and_register(pib[0], t1[0], subj_out_dir, "PET_PIB")

        # Resample VOIs to T1 space (once per subject)
        voi_ctx_t1 = transform_mask_to_t1(args.voi_ctx, t1[0], subj_out_dir, "ctx")
        voi_wc_t1 = transform_mask_to_t1(args.voi_wc, t1[0], subj_out_dir, "wc")

        # Grid sanity check
        if not check_same_grid(fbb_t1, voi_ctx_t1):
            print(f"⚠️  Skipping {subj_id}: PET and mask grid mismatch.")
            continue

        # ROI means
        fbb_ctx_mean = extract_mean_in_mask(fbb_t1, voi_ctx_t1)
        fbb_ref_mean = extract_mean_in_mask(fbb_t1, voi_wc_t1)
        pib_ctx_mean = extract_mean_in_mask(pib_t1, voi_ctx_t1)
        pib_ref_mean = extract_mean_in_mask(pib_t1, voi_wc_t1)

        fbb_suvr = fbb_ctx_mean / fbb_ref_mean if fbb_ref_mean > 0 else np.nan
        pib_suvr = pib_ctx_mean / pib_ref_mean if pib_ref_mean > 0 else np.nan

        rows.append({
            "subj": subj_id,
            "fbb_suvr": fbb_suvr,
            "pib_suvr": pib_suvr
        })

    # ================================
    # SUVR analysis and calibration
    # ================================
    df = pd.DataFrame(rows)
    raw_csv = os.path.join(args.outdir, "calibration_raw_suvr.csv")
    df.to_csv(raw_csv, index=False)
    print(f"\n💾 Saved raw SUVRs: {raw_csv}")

    df_good = df.dropna(subset=['fbb_suvr', 'pib_suvr'])
    if df_good.empty:
        print("❌ No valid SUVR pairs found.")
        return

    # Linear regression
    slope, intercept, r, p, se = linregress(df_good['fbb_suvr'], df_good['pib_suvr'])
    print(f"\n📈 Regression: PiB_calc = {slope:.4f} * FBB_SUVR + {intercept:.4f} (R²={r**2:.3f})")

    df_good['pib_calc'] = slope * df_good['fbb_suvr'] + intercept

    # YC/AD estimation
    yc_mask = df_good['subj'].str.contains("YC", case=False)
    ad_mask = df_good['subj'].str.contains("E", case=False)

    mean_pib_yc = df_good.loc[yc_mask, 'pib_suvr'].mean()
    mean_pib_ad = df_good.loc[ad_mask, 'pib_suvr'].mean()
    if np.isnan(mean_pib_yc) or np.isnan(mean_pib_ad):
        mean_pib_yc = df_good['pib_suvr'].quantile(0.1)
        mean_pib_ad = df_good['pib_suvr'].quantile(0.9)

    # Centiloid coefficients
    A = 100 * slope / (mean_pib_ad - mean_pib_yc)
    B = 100 * (intercept - mean_pib_yc) / (mean_pib_ad - mean_pib_yc)

    df_good['centiloid'] = A * df_good['fbb_suvr'] + B
    results_csv = os.path.join(args.outdir, "calibration_results.csv")
    df_good.to_csv(results_csv, index=False)
    print(f"💾 Saved calibration results: {results_csv}")

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


# ================================
# Entry point
# ================================
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, help="Root folder containing GAAIN subjects")
    parser.add_argument("--outdir", required=True, help="Output directory for results")
    parser.add_argument("--voi_ctx", required=True, help="Path to cortical target VOI mask")
    parser.add_argument("--voi_wc", required=True, help="Path to whole cerebellum VOI mask")
    args = parser.parse_args()
    main(args)
