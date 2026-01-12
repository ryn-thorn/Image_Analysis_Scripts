#!/usr/bin/env python

import os
import sys
import nibabel as nib
import numpy as np
import pandas as pd

def main(mgz_folder):
    output_folder = os.path.join(mgz_folder, "nii_converted")
    os.makedirs(output_folder, exist_ok=True)

    all_rows = []

    for file in os.listdir(mgz_folder):
        if file.endswith(".mgz"):
            mgz_path = os.path.join(mgz_folder, file)
            nii_filename = file.replace(".mgz", ".nii")
            nii_path = os.path.join(output_folder, nii_filename)

            # Load .mgz
            img = nib.load(mgz_path)
            data = img.get_fdata()

            # Convert to integer for counting discrete voxel intensities
            data_int = np.round(data).astype(np.int32)

            # Count voxels
            unique, counts = np.unique(data_int, return_counts=True)

            # Append to master list
            for val, cnt in zip(unique, counts):
                all_rows.append({
                    "ROI": file.replace(".mgz", ""),
                    "Value": val,
                    "VoxelCount": cnt
                })

            # Save NIfTI
            nib.save(nib.Nifti1Image(data, img.affine, img.header), nii_path)
            print(f"Processed {file} -> {nii_filename}")

    # Save master CSV
    master_csv_path = os.path.join(output_folder, "mgz_voxel_counts_master.csv")
    df_master = pd.DataFrame(all_rows)
    df_master.to_csv(master_csv_path, index=False)
    print("Master CSV saved:", master_csv_path)
    print("All files processed.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python mgz_to_nii_voxelcount_master.py <mgz_folder_path>")
        sys.exit(1)

    mgz_folder = sys.argv[1]
    if not os.path.isdir(mgz_folder):
        print("Error: Folder does not exist:", mgz_folder)
        sys.exit(1)

    main(mgz_folder)
