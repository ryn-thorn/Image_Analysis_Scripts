#!/usr/bin/env python3
"""
Optimized FBP Centiloid calibration script using GAAIN paired PiB+FBP dataset
and AVID VOIs, with MNI->T1 warp computed once per subject.

Workflow:
1. Compute MNI -> T1 warp (FLIRT + FNIRT) once per subject.
2. Apply warp to merged target VOI and reference VOI (MNI->T1).
3. Register PETs (FBP & PiB) to T1 space.
4. Compute SUVRs and Centiloids.

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
import nibabel as nib
from scipy.stats import linregress
from concurrent.futures import ProcessPoolExecutor, as_completed

# ================================
# Utility functions
# ================================
def run_cmd(cmd):
    print("CMD:", " ".join(cmd))
    subprocess.check_call(cmd)

def safe_run_cmd(cmd, outfile=None):
    if outfile and os.path.exists(outfile):
        print(f"✅ Skipping step: {os.path.basename(outfile)} already exists.")
        return
    run_cmd(cmd)

def truncate_4d_to_3d(img_path, out_path):
    img = nib.load(img_path)
    if len(img.shape) == 4:
        print(f"⚠️  {os.path.basename(img_path)} is 4D, truncating to first volume")
        img_3d = nib.Nifti1Image(img.dataobj[..., 0], img.affine, img.header)
        nib.save(img_3d, out_path)
    else:
        if img_path != out_path:
            run_cmd(['cp', img_path, out_path])

def merge_target_vois(target_dir, out_mask):
    voi_list = sorted(glob.glob(os.path.join(target_dir, "*.nii*")))
    if not voi_list:
        raise FileNotFoundError(f"No VOIs found in {target_dir}")
    print(f"🧩 Merging {len(voi_list)} target VOIs into one composite mask")
    tmp = voi_list[0]
    for voi in voi_list[1:]:
        run_cmd(['fslmaths', tmp, '-add', voi, tmp])
    run_cmd(['fslmaths', tmp, '-bin', out_mask])
    return out_mask

def pet_registration(pet_img, t1_img, pet_std, pet_t1):
    """Reorient and register PET directly to T1 (no threshold/reslice)."""
    safe_run_cmd(['fslreorient2std', pet_img, pet_std], pet_std)
    truncate_4d_to_3d(pet_std, pet_std)
    safe_run_cmd(['flirt', '-ref', t1_img, '-in', pet_std, '-out', pet_t1], pet_t1)
    return pet_t1

def linear_flirt_mni_to_t1(mni_template, t1_img, out_affine):
    """Compute initial FLIRT affine: MNI -> T1."""
    safe_run_cmd([
        'flirt', '-in', mni_template, '-ref', t1_img,
        '-omat', out_affine, '-dof', '12'
    ], out_affine)
    return out_affine

def nonlinear_fnirt_mni_to_t1(mni_template, t1_img, affine_mat, out_warp):
    """Compute nonlinear warp from MNI -> T1 using FNIRT, initialized with affine."""
    safe_run_cmd([
        'fnirt',
        '--in=' + mni_template,
        '--aff=' + affine_mat,
        '--ref=' + t1_img,
        '--cout=' + out_warp
    ], out_warp)
    return out_warp

def apply_warp_to_voi(voi_img, t1_img, warp_file, out_mask):
    """Apply FNIRT warp to VOI to bring it into subject T1 space."""
    safe_run_cmd([
        'applywarp',
        '--ref=' + t1_img,
        '--in=' + voi_img,
        '--warp=' + warp_file,
        '--out=' + out_mask,
        '--interp=nn'
    ], out_mask)
    return out_mask

def extract_mean_in_mask(img, mask):
    """Compute mean uptake in mask using fslstats."""
    try:
        out = subprocess.check_output(['fslstats', img, '-k', mask, '-M'])
        return float(out.decode().strip())
    except subprocess.CalledProcessError:
        return np.nan

# ================================
# Wrapper to process a single subject
# ================================
def process_single_subject(subj_path, merged_ctx_mni, args):
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
        return None

    # Reorient images
    fbp_reor = os.path.join(subj_out_dir, "PET_FBP_reor.nii.gz")
    pib_reor = os.path.join(subj_out_dir, "PET_PIB_reor.nii.gz")
    t1_reor = os.path.join(subj_out_dir, "T1_reor.nii.gz")
    safe_run_cmd(['fslreorient2std', fbp[0], fbp_reor], fbp_reor)
    safe_run_cmd(['fslreorient2std', pib[0], pib_reor], pib_reor)
    safe_run_cmd(['fslreorient2std', t1[0], t1_reor], t1_reor)

    # Step 1: MNI -> T1 warp
    affine_file = os.path.join(subj_out_dir, "mni2t1_affine.mat")
    warp_file = os.path.join(subj_out_dir, "mni2t1_warp.nii.gz")
    mni_template = '/usr/local/fsl/data/standard/MNI152_T1_1mm.nii.gz'
    linear_flirt_mni_to_t1(mni_template, t1_reor, affine_file)
    nonlinear_fnirt_mni_to_t1(mni_template, t1_reor, affine_file, warp_file)

    # Apply warp to VOIs
    merged_ctx_t1 = os.path.join(subj_out_dir, "composite_ctx_mask_T1.nii.gz")
    voi_ref_t1 = os.path.join(subj_out_dir, "voi_ref_T1.nii.gz")
    apply_warp_to_voi(merged_ctx_mni, t1_reor, warp_file, merged_ctx_t1)
    apply_warp_to_voi(args.voi_ref, t1_reor, warp_file, voi_ref_t1)

    # Step 2: Register PETs to T1
    fbp_pet_t1 = pet_registration(fbp_reor, t1_reor,
                                  os.path.join(subj_out_dir, "PET_FBP_pet_std.nii.gz"),
                                  os.path.join(subj_out_dir, "PET_FBP_pet_t1.nii.gz"))
    pib_pet_t1 = pet_registration(pib_reor, t1_reor,
                                  os.path.join(subj_out_dir, "PET_PIB_pet_std.nii.gz"),
                                  os.path.join(subj_out_dir, "PET_PIB_pet_t1.nii.gz"))

    # Step 3: Compute ROI means
    fbp_ctx_mean = extract_mean_in_mask(fbp_pet_t1, merged_ctx_t1)
    fbp_ref_mean = extract_mean_in_mask(fbp_pet_t1, voi_ref_t1)
    pib_ctx_mean = extract_mean_in_mask(pib_pet_t1, merged_ctx_t1)
    pib_ref_mean = extract_mean_in_mask(pib_pet_t1, voi_ref_t1)

    fbp_suvr = fbp_ctx_mean / fbp_ref_mean if fbp_ref_mean > 0 else np.nan
    pib_suvr = pib_ctx_mean / pib_ref_mean if pib_ref_mean > 0 else np.nan

    return {"subj": subj_id, "fbp_suvr": fbp_suvr, "pib_suvr": pib_suvr}

# ================================
# Main analysis
# ================================
def main(args):
    os.makedirs(args.outdir, exist_ok=True)

    # Merge target VOIs once (MNI space)
    merged_ctx_mni = os.path.join(args.outdir, "composite_ctx_mask_MNI.nii.gz")
    if not os.path.exists(merged_ctx_mni):
        merge_target_vois(args.voi_targets, merged_ctx_mni)

    subj_dirs = sorted(glob.glob(os.path.join(args.root, "*")))
    rows = []

    # Process subjects in parallel
    with ProcessPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(process_single_subject, subj, merged_ctx_mni, args): subj
                   for subj in subj_dirs}

        for future in as_completed(futures):
            result = future.result()
            if result:
                rows.append(result)
                print(f"✅ Finished {result['subj']}")

    # SUVR analysis & Centiloid calculation (unchanged)
    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(args.outdir, "calibration_raw_suvr.csv"), index=False)

    df_good = df.dropna(subset=['fbp_suvr', 'pib_suvr'])
    if df_good.empty:
        print("❌ No valid SUVR pairs found.")
        return

    slope, intercept, r, p, se = linregress(df_good['fbp_suvr'], df_good['pib_suvr'])
    df_good['pib_calc'] = slope * df_good['fbp_suvr'] + intercept

    yc_mask = df_good['subj'].str.contains("YC", case=False)
    ad_mask = df_good['subj'].str.contains("E", case=False)

    mean_pib_yc = df_good.loc[yc_mask, 'pib_suvr'].mean()
    mean_pib_ad = df_good.loc[ad_mask, 'pib_suvr'].mean()
    if np.isnan(mean_pib_yc) or np.isnan(mean_pib_ad):
        mean_pib_yc = df_good['pib_suvr'].quantile(0.1)
        mean_pib_ad = df_good['pib_suvr'].quantile(0.9)

    A = 100 * slope / (mean_pib_ad - mean_pib_yc)
    B = 100 * (intercept - mean_pib_yc) / (mean_pib_ad - mean_pib_yc)
    df_good['centiloid'] = A * df_good['fbp_suvr'] + B

    df_good.to_csv(os.path.join(args.outdir, "calibration_results.csv"), index=False)

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

# ================================
# Entry point
# ================================
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, help="Root folder containing GAAIN subjects")
    parser.add_argument("--outdir", required=True, help="Output directory for results")
    parser.add_argument("--voi_targets", required=True, help="Folder containing target VOIs (multiple .nii.gz)")
    parser.add_argument("--voi_ref", required=True, help="Path to reference VOI mask (e.g., cere_all.nii.gz)")
    args = parser.parse_args()
    main(args)
