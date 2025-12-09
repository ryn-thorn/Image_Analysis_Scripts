#!/usr/bin/env python
"""
BIDS_pet_converter.py

Converts PET DICOMs stored in ZIP files to BIDS-compliant NIfTI files.
All files are assumed to be session Y0.

Usage:
    python BIDS_pet_converter.py --input /path/to/00_pet_zipped --bids /path/to/BIDS_root
"""

import argparse
import logging
import zipfile
import shutil
import subprocess
from pathlib import Path
from tqdm import tqdm
import tempfile

# ---------------- File Names ----------------
STRING_MAP = {
    "PET_Brain_(calculated_AC)": "PET_Brain-Calc_AC",
    "PET_Brain_AC": "PET_Brain-AC",
    "PET_MU_MAP_PET_Brain_(calculated_AC)": "PET_Brain-MU_MAP-Calc_AC",
    "PET_Statistics": "PET_Statistics"
}

LOG_FILENAME = "BIDS_pet_conversion.log"
ERROR_LOG_FILENAME = "BIDS_pet_conversion_errors.log"

# ---------------- Functions ----------------
def unzip_file(zip_path: Path, extract_to: Path):
    with zipfile.ZipFile(zip_path, "r") as zip_ref:
        zip_ref.extractall(extract_to)

def run_dcm2niix(dicom_folder: Path, output_folder: Path):
    """Run dcm2niix on dicom_folder, output to output_folder"""
    # Use compression 0 to keep unzipped nifti files
    cmd = ["dcm2niix", "-z", "n", "-o", str(output_folder), str(dicom_folder)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"dcm2niix failed:\n{result.stderr}")
    return output_folder

def rename_and_move_files(subject: str, temp_dir: Path, bids_dir: Path):
    pet_dir = bids_dir / f"sub-{subject}" / "ses-Y0" / "pet"
    pet_dir.mkdir(parents=True, exist_ok=True)
    
    for f in temp_dir.iterdir():
        if not f.is_file():
            continue
        
        # Skip BRAIN_MUSC files
        if f.stem.startswith("BRAIN_MUSC"):
            f.unlink()
            continue

        # Determine new name
        new_stem = STRING_MAP.get(f.stem, None)
        if new_stem is None:
            logging.info(f"Skipping unknown file {f.name}")
            continue

        new_name = f"sub-{subject}_ses-Y0_{new_stem}{f.suffix}"
        dst = pet_dir / new_name
        shutil.move(str(f), dst)
        logging.info(f"{f.name} → {dst}")

def process_pet(input_dir: Path, bids_dir: Path):
    logging.info("Starting PET BIDS conversion...")

    error_log = bids_dir / ERROR_LOG_FILENAME
    if error_log.exists():
        error_log.unlink()

    zip_files = list(input_dir.glob("IAM_*.zip"))
    logging.info(f"Found {len(zip_files)} zip files.")

    for zip_file in tqdm(zip_files, desc="Processing subjects"):
        try:
            subject_id = zip_file.stem.replace("IAM_", "")
            with tempfile.TemporaryDirectory() as tmpdirname:
                tmpdir = Path(tmpdirname)
                # Extract
                unzip_file(zip_file, tmpdir)
                # Convert
                run_dcm2niix(tmpdir, tmpdir)
                # Rename and move to BIDS
                rename_and_move_files(subject_id, tmpdir, bids_dir)
        except Exception as e:
            logging.error(f"Failed processing {zip_file.name}: {e}")
            with error_log.open("a") as f:
                f.write(f"{zip_file.name}: {repr(e)}\n")

    logging.info("PET conversion complete.")

# ---------------- CLI ----------------
def main():
    parser = argparse.ArgumentParser(description="Convert PET ZIPs to BIDS NIfTI")
    parser.add_argument("--input", required=True, type=str, help="Folder containing PET ZIP files")
    parser.add_argument("--bids", required=True, type=str, help="Root BIDS folder")
    args = parser.parse_args()

    input_dir = Path(args.input)
    bids_dir = Path(args.bids)
    bids_dir.mkdir(parents=True, exist_ok=True)

    logging.basicConfig(
        filename=bids_dir / LOG_FILENAME,
        filemode="a",
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s"
    )
    logging.info(f"Input folder: {input_dir}")
    logging.info(f"BIDS root: {bids_dir}")

    process_pet(input_dir, bids_dir)

if __name__ == "__main__":
    main()
