#!/usr/bin/env python3
#
# usage: ./fs_complete.py /MRI/03_nii /freesurfer_7.2/ /freesurfer_7.2/_check.csv

import os
import csv
import sys

def has_t1(anat_dir):
    """Return True if a T1-like file is present."""
    if not os.path.isdir(anat_dir):
        return False
    for f in os.listdir(anat_dir):
        name = f.lower()
        if name.endswith((".nii", ".nii.gz")) and "t1" in name:
            return True
    return False


def check_fs_output(subj_fs_dir):
    """Check Freesurfer outputs for completeness and version info."""
    results = {
        "aparc+aseg_present": False,
        "aseg_present": False,
        "recon_all_log_found": False,
        "finished_message": "NA",
        "recon_all_version": "NA",
    }

    # Handle both direct and nested folder cases
    possible_dirs = [subj_fs_dir]
    nested = os.path.join(subj_fs_dir, os.path.basename(subj_fs_dir))
    if os.path.isdir(nested):
        possible_dirs.append(nested)

    subj_dir = None
    for d in possible_dirs:
        if os.path.isdir(os.path.join(d, "mri")):
            subj_dir = d
            break
    if subj_dir is None:
        return results

    # MRI checks
    results["aparc+aseg_present"] = os.path.isfile(os.path.join(subj_dir, "mri", "aparc+aseg.mgz"))
    results["aseg_present"] = os.path.isfile(os.path.join(subj_dir, "mri", "aseg.mgz"))

    # recon-all.log checks
    log_path = os.path.join(subj_dir, "scripts", "recon-all.log")
    if os.path.isfile(log_path):
        results["recon_all_log_found"] = True
        try:
            with open(log_path, "r", errors="ignore") as f:
                lines = f.readlines()
            for line in reversed(lines):
                if "finished without error" in line or "error" in line.lower():
                    results["finished_message"] = line.strip()
                    break
        except Exception as e:
            results["finished_message"] = f"Error reading log: {e}"

    # Version check
    version_file = os.path.join(subj_dir, "scripts", "build-stamp.txt")
    if os.path.isfile(version_file):
        try:
            with open(version_file, "r", errors="ignore") as vf:
                version_text = vf.read().strip().replace("\n", " ")
            results["recon_all_version"] = version_text
        except Exception as e:
            results["recon_all_version"] = f"Error reading version: {e}"

    return results


def main(raw_base, fs_base, output_csv):
    rows = []

    # Loop over subjects: sub-*
    for subj in sorted(os.listdir(raw_base)):
        subj_root = os.path.join(raw_base, subj)
        if not os.path.isdir(subj_root):
            continue

        # Loop over visit folders inside subject: Y0 / Y2 / Y4 / Y6 etc.
        for visit in sorted(os.listdir(subj_root)):
            visit_dir = os.path.join(subj_root, visit)
            if not os.path.isdir(visit_dir):
                continue

            anat_dir = os.path.join(visit_dir, "anat")
            if not os.path.isdir(anat_dir):
                continue

            # Check T1 in anat
            raw_t1 = has_t1(anat_dir)

            # Freesurfer folder now depends on *both* subject and visit
            subj_fs_dir = os.path.join(fs_base, subj, visit)

            fs_present = os.path.isdir(subj_fs_dir)
            fs_info = check_fs_output(subj_fs_dir) if fs_present else {
                "aparc+aseg_present": False,
                "aseg_present": False,
                "recon_all_log_found": False,
                "finished_message": "NA",
                "recon_all_version": "NA",
            }

            rows.append({
                "SubjID": subj,
                "Visit": visit,
                "Raw_T1_found": raw_t1,
                "FS_folder_found": fs_present,
                **fs_info
            })

    # Write CSV
    with open(output_csv, "w", newline="") as csvfile:
        fieldnames = [
            "SubjID",
            "Visit",
            "Raw_T1_found",
            "FS_folder_found",
            "aparc+aseg_present",
            "aseg_present",
            "recon_all_log_found",
            "finished_message",
            "recon_all_version",
        ]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    # Summary
    total = len(rows)
    complete = sum(1 for r in rows if r["FS_folder_found"] and r["aseg_present"] and r["aparc+aseg_present"])
    print(f"Summary written to {output_csv}")
    print(f"Total subject-visits checked: {total}")
    print(f"Complete Freesurfer outputs: {complete}")
    print(f"Incomplete or missing: {total - complete}")



if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: fs_complete.py /path/to/raw_base /path/to/freesurfer_base /path/to/output.csv")
        sys.exit(1)

    raw_base = sys.argv[1]
    fs_base = sys.argv[2]
    output_csv = sys.argv[3]
    main(raw_base, fs_base, output_csv)
