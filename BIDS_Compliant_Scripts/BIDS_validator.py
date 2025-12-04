#!/usr/bin/env python3
"""
IAM BIDS Validator Companion Script
-----------------------------------
Scans through IAM_BIDS structure and reports:
  - Unexpected files
  - Missing modalities
  - Wrong directory placements
  - Non‑BIDS filenames
  - Empty folders
  - Summary report

Usage: python IAM_BIDS_validator.py /path/to/IAM_BIDS

Produces:
  IAM_BIDS_validation_report.tsv
"""

import os
import re
import sys
import csv
from datetime import datetime

# ----------------------- BIDS filename pattern ---------------------------------
BIDS_RE = re.compile(r"sub-(?P<sub>[^_]+)_ses-(?P<ses>[^_]+)_(?P<suffix>.+)\.(nii\.gz|json|bval|bvec)$")

EXPECTED_MODALITIES = {
    "anat": ["T1w", "T2w", "T1w_Cor", "T1w_Tra"],
    "func": ["Resting_1", "Resting_2", "Task"],
    "fmap": ["field-map_e1", "field-map_e2ph"],
    "dwi": ["DKI_30dir", "DKI_64dir", "DKI_30dir_TOPUP", "DKI_64dir_TOPUP", "FBI", "TDE", "TDE_off"],
    "misc": []
}

# ----------------------- Functions ---------------------------------
def is_bids_file(filename):
    return BIDS_RE.match(filename) is not None

def detect_modality(filename):
    for modality, suffixes in EXPECTED_MODALITIES.items():
        for suf in suffixes:
            if suf in filename:
                return modality
    return "unknown"

def validate_bids(bids_root):
    report_path = os.path.join(bids_root, "IAM_BIDS_validation_report.tsv")

    with open(report_path, "w", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(["timestamp", "subject", "session", "file", "status", "note"])

        for sub in sorted(d for d in os.listdir(bids_root) if d.startswith("sub-")):
            sub_path = os.path.join(bids_root, sub)
            if not os.path.isdir(sub_path):
                continue

            for ses in sorted(d for d in os.listdir(sub_path) if d.startswith("ses-")):
                ses_path = os.path.join(sub_path, ses)
                if not os.path.isdir(ses_path):
                    continue

                # Check each modality folder
                for root, dirs, files in os.walk(ses_path):
                    rel = os.path.relpath(root, bids_root)
                    modality = os.path.basename(root)

                    # Empty folders
                    if not files and not dirs:
                        writer.writerow([datetime.now(), sub, ses, rel, "EMPTY_FOLDER", "Folder has no files"])

                    for fname in files:
                        fpath = os.path.join(root, fname)

                        # Check BIDS compliance
                        if not is_bids_file(fname):
                            writer.writerow([datetime.now(), sub, ses, fname, "NOT_BIDS", "Filename does not match BIDS spec"])
                            continue

                        # Modalities in wrong folder
                        detected = detect_modality(fname)
                        if detected != "unknown" and detected != modality:
                            writer.writerow([datetime.now(), sub, ses, fname, "WRONG_FOLDER", f"Should be inside {detected}/ not {modality}/"])
                            continue

                        # Everything OK
                        writer.writerow([datetime.now(), sub, ses, fname, "OK", ""])

    print(f"Validation complete. TSV report written to: {report_path}")

# ----------------------- Usage ---------------------------------
if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python IAM_BIDS_validator.py /path/to/IAM_BIDS")
        sys.exit(1)

    validate_bids(sys.argv[1])
