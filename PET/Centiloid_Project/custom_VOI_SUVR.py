#!/usr/bin/env python3
"""
Pipeline to register VOIs to subject T1, binarize, resample to PET, and compute SUVRs.
- VOIs: VOI_std.nii.gz, VOI_ref_std.nii.gz
- MR selection: MR*.nii or MR*.nii.gz
- Resample: nearest-neighbor to PET voxel grid

python3 process_calibration_pipeline.py \
  --ref /Users/kayti/Desktop/Projects/IAM/Centiloids/Calibration/Florbetapir/nifti \
  --voi /Users/kayti/Desktop/Projects/IAM/Centiloids/VOIs \
  --out /Users/kayti/Desktop/Projects/IAM/Centiloids/Calibration/Florbetapir/calibration \
  --pet PIB FBP

"""

import os
import subprocess
import nibabel as nib
import numpy as np
import csv
import argparse

def flirt_register(in_file, ref_file, out_file, omat_file=None, applyxfm=False):
    cmd = ["flirt", "-in", in_file, "-ref", ref_file, "-out", out_file]
    if applyxfm and omat_file:
        cmd += ["-applyxfm", "-init", omat_file]
    else:
        if omat_file:
            cmd += ["-omat", omat_file]
    subprocess.run(cmd, check=True)

def binarize_nifti(in_file, out_file):
    subprocess.run(["fslmaths", in_file, "-bin", out_file], check=True)

def resample_to_pet(mask_file, pet_file, out_file):
    # nearest-neighbor resampling to PET grid
    cmd = [
        "flirt",
        "-in", mask_file,
        "-ref", pet_file,
        "-out", out_file,
        "-applyxfm",
        "-usesqform",
        "-interp", "nearestneighbour"
    ]
    subprocess.run(cmd, check=True)

def compute_mean_suvr(pet_file, voi_file):
    pet = nib.load(pet_file).get_fdata()
    voi = nib.load(voi_file).get_fdata()
    mask = voi > 0
    if np.any(mask):
        return np.mean(pet[mask])
    else:
        return np.nan

def main():
    parser = argparse.ArgumentParser(description="VOI registration and SUVR pipeline")
    parser.add_argument("--ref", required=True, help="Folder with subject subfolders containing MR*.nii files")
    parser.add_argument("--voi", required=True, help="Folder with VOI_std.nii.gz, VOI_ref_std.nii.gz, T1_std.nii.gz")
    parser.add_argument("--out", required=True, help="Folder to store outputs")
    parser.add_argument("--pet", nargs="+", default=["PIB","FBB"], help="PET tracer suffixes in PET_<suffix>_pet_t1.nii.gz")
    args = parser.parse_args()

    ref_mri_folder = args.ref
    voi_folder = args.voi
    output_folder = args.out
    pet_suffixes = args.pet

    os.makedirs(output_folder, exist_ok=True)

    voi_files = ["VOI_std.nii.gz", "VOI_ref_std.nii.gz"]

    results = []

    for subj_id in sorted(os.listdir(ref_mri_folder)):
        subj_folder = os.path.join(ref_mri_folder, subj_id)
        if not os.path.isdir(subj_folder):
            continue

        # Hardcoded MR selection
        mr_files = [f for f in os.listdir(subj_folder) if f.startswith("MR") and (f.endswith(".nii") or f.endswith(".nii.gz"))]
        if len(mr_files) == 0:
            print(f"⚠️ No MRI found for {subj_id}, skipping.")
            continue
        subj_mri_path = os.path.join(subj_folder, mr_files[0])

        subj_outdir = os.path.join(output_folder, subj_id)
        os.makedirs(subj_outdir, exist_ok=True)

        print(f"\nProcessing subject {subj_id}...")

        # Step 1: Register T1 template to subject T1
        flirt_omat = os.path.join(subj_outdir, "VOIs2subj.mat")
        flirt_register(
            os.path.join(voi_folder, "T1_std.nii.gz"),
            subj_mri_path,
            os.path.join(subj_outdir, "T1_std2subj.nii.gz"),
            omat_file=flirt_omat
        )

        # Step 2: Apply transform to VOIs and binarize
        voi_registered = {}
        for voi in voi_files:
            voi_in = os.path.join(voi_folder, voi)
            voi_out = os.path.join(subj_outdir, voi.replace(".nii.gz","_2subj.nii.gz"))
            flirt_register(voi_in, subj_mri_path, voi_out, omat_file=flirt_omat, applyxfm=True)

            voi_bin_out = os.path.join(subj_outdir, voi.replace(".nii.gz","_2subj_bin.nii.gz"))
            binarize_nifti(voi_out, voi_bin_out)
            voi_registered[voi] = voi_bin_out

        # Step 3: Compute SUVRs for each PET tracer
        subj_result = {"SubjectID": subj_id}
        for suffix in pet_suffixes:
            pet_file = os.path.join(subj_outdir, f"PET_{suffix}_pet_t1.nii.gz")
            if os.path.exists(pet_file):
                # Resample VOIs to PET voxel grid
                target_resampled = os.path.join(subj_outdir, f"VOI_std_2PET_{suffix}.nii.gz")
                ref_resampled = os.path.join(subj_outdir, f"VOI_ref_std_2PET_{suffix}.nii.gz")
                resample_to_pet(voi_registered["VOI_std.nii.gz"], pet_file, target_resampled)
                resample_to_pet(voi_registered["VOI_ref_std.nii.gz"], pet_file, ref_resampled)

                mean_target = compute_mean_suvr(pet_file, target_resampled)
                mean_ref = compute_mean_suvr(pet_file, ref_resampled)
                suvr = mean_target / mean_ref if mean_ref != 0 else np.nan
                subj_result[f"SUVR_{suffix}"] = suvr
            else:
                subj_result[f"SUVR_{suffix}"] = np.nan

        results.append(subj_result)

    # Save CSV
    csv_file = os.path.join(output_folder, "SUVR_results.csv")
    fieldnames = ["SubjectID"] + [f"SUVR_{s}" for s in pet_suffixes]
    with open(csv_file, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"\n✅ Finished. SUVRs saved to {csv_file}")

if __name__ == "__main__":
    main()
