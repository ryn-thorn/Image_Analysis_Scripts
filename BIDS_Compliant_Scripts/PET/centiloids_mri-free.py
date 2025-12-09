#!/usr/bin/env python3

import os
import subprocess
import argparse
import nibabel as nib
import numpy as np
import csv

# FSL MNI template path (update if needed)
MNI_TEMPLATE = "/usr/local/fsl/data/standard/MNI152_T1_1mm.nii.gz"

def run(cmd):
    """Run a shell command and check for errors."""
    print(f"Running: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)

def linear_register(in_file, ref_file, out_file):
    """Linear registration using FLIRT."""
    run(['flirt', '-in', in_file, '-ref', ref_file, '-out', out_file, '-omat', out_file.replace('.nii.gz','.mat')])

def nonlinear_register(in_file, ref_file, out_file):
    """Nonlinear registration using FNIRT."""
    mat_file = in_file.replace('.nii.gz','.mat')
    run(['fnirt', '--in=' + in_file, '--aff=' + mat_file, '--ref=' + ref_file, '--iout=' + out_file])

def average_images(image_files, out_file):
    """Average a list of images."""
    tmp = image_files[0]
    cmd = ['fslmaths', tmp, '-add', tmp, '-div', '2', out_file] if len(image_files) == 2 else None

    if len(image_files) > 2:
        # Start with first image
        run(['fslmaths', image_files[0], '-add', image_files[1], '-div', '2', out_file])
        for img in image_files[2:]:
            run(['fslmaths', out_file, '-add', img, '-div', '2', out_file])

def extract_roi_values(nii_file, roi_file):
    """Extract mean intensity within ROI."""
    img = nib.load(nii_file).get_fdata()
    roi = nib.load(roi_file).get_fdata()
    values = img[roi > 0]
    return float(np.mean(values))

def process_input_folder(input_folder, file_patterns, roi_files, csv_writer):
    # Step 1: Find all files
    subfolders = [os.path.join(input_folder, d) for d in os.listdir(input_folder)
                  if os.path.isdir(os.path.join(input_folder,d))]
    
    for pattern in file_patterns:
        linear_registered_files = []
        # Linear registration to MNI
        for sub in subfolders:
            subjID = os.path.basename(sub)
            file_path = os.path.join(sub, pattern)
            if not os.path.exists(file_path):
                continue
            out_file = os.path.join(sub, pattern.replace('.nii.gz','_MNI.nii.gz'))
            linear_register(file_path, MNI_TEMPLATE, out_file)
            linear_registered_files.append(out_file)
        
        # Average the linear-registered images
        avg_file = os.path.join(input_folder, f"average_{pattern.replace('.nii.gz','_MNI.nii.gz')}")
        average_images(linear_registered_files, avg_file)
        
        # Nonlinear registration of original files to average map
        for sub in subfolders:
            file_path = os.path.join(sub, pattern)
            if not os.path.exists(file_path):
                continue
            out_file = os.path.join(sub, pattern.replace('.nii.gz','_MNI.nii.gz'))
            nonlinear_register(file_path, avg_file, out_file)
            
            # Extract ROI values
            roi_vals = {}
            for roi_name, roi_file in roi_files.items():
                roi_vals[roi_name] = extract_roi_values(out_file, roi_file)
            
            # Write to CSV
            csv_writer.writerow([os.path.basename(sub), os.path.basename(out_file), roi_vals['ctx'], roi_vals['WhlCbl']])

def main():
    parser = argparse.ArgumentParser(description="PET Registration and ROI extraction script")
    parser.add_argument('--fbb', required=True, help='Path to FBB folder')
    parser.add_argument('--fbp', required=True, help='Path to FBP folder')
    parser.add_argument('--roi_ctx', required=True, help='Path to voi_ctx_1mm.nii')
    parser.add_argument('--roi_cbl', required=True, help='Path to voi_WhlCbl_1mm.nii')
    parser.add_argument('--output_csv', default='roi_values.csv', help='Output CSV file')
    
    args = parser.parse_args()
    
    roi_files = {
        'ctx': args.roi_ctx,
        'WhlCbl': args.roi_cbl
    }
    
    with open(args.output_csv, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['subjID', 'file', 'ctx', 'WhlCbl'])
        
        # Process FBB folder
        process_input_folder(args.fbb, ['PET_FBB.nii.gz', 'PET_PiB.nii.gz'], roi_files, writer)
        # Process FBP folder
        process_input_folder(args.fbp, ['florbetapir.nii.gz', 'PiB.nii.gz'], roi_files, writer)

if __name__ == "__main__":
    main()
