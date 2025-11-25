#!/usr/bin/env python

"""
BIDS_derivative_organizer.py

Purpose:
    Copy and reorganize derivative outputs into BIDS-style folder structure.
    Automatically handles suffix → session mapping:
        no suffix → ses-Y0
        b → ses-Y2
        c → ses-Y4
        d → ses-Y6
    Preserves symlinks (important for FreeSurfer outputs).
    Logs operations and reports any failed copies.

Usage:
    python BIDS_derivative_organizer.py --input INPUT_DIR --output OUTPUT_DIR --prefix IAM_

Dependencies:
    - Python 3.8+
    - tqdm (for progress bar)
"""

import argparse
import logging
import shutil
from pathlib import Path
from tqdm import tqdm

# ---------------- CONFIG ----------------
SUFFIX_SESSION_MAP = {
    "": "ses-Y0",
    "b": "ses-Y2",
    "c": "ses-Y4",
    "d": "ses-Y6"
}

LOG_FILENAME = "BIDS_derivative_copy.log"
ERROR_LOG_FILENAME = "BIDS_derivative_copy_errors.log"

# ---------------- HELPERS ----------------
def parse_subject_suffix(folder_name: str, prefix: str):
    """
    Given folder like IAM_1001b or IAM_1002, return (subject_number, suffix)
    """
    if not folder_name.startswith(prefix):
        return None, None
    remainder = folder_name[len(prefix):]  # strip prefix
    if remainder[-1].lower() in ("b", "c", "d"):
        return remainder[:-1], remainder[-1].lower()
    else:
        return remainder, ""

def ensure_dir(path: Path):
    path.mkdir(parents=True, exist_ok=True)
    return path

def copy_folder(src: Path, dst: Path, error_log: Path):
    """
    Copy src to dst preserving symlinks.
    On failure, log to error_log but continue.
    """
    try:
        shutil.copytree(src, dst, dirs_exist_ok=True, symlinks=True)
        logging.info(f"Copied {src} → {dst}")
        return True
    except Exception as e:
        with error_log.open("a") as f:
            f.write(f"{src} → {dst}: {repr(e)}\n")
        logging.warning(f"Failed to copy {src} → {dst}: {e}")
        return False

# ---------------- MAIN FUNCTION ----------------
def convert_structure(input_dir: Path, output_dir: Path, prefix: str):
    logging.info("Starting BIDS derivative copy conversion...")

    error_log = output_dir / ERROR_LOG_FILENAME
    if error_log.exists():
        error_log.unlink()  # reset error log

    # Detect all subject folders in input_dir
    subject_folders = [p for p in input_dir.iterdir() if p.is_dir() and p.name.startswith(prefix)]
    base_subjects = sorted({parse_subject_suffix(p.name, prefix)[0] for p in subject_folders if parse_subject_suffix(p.name, prefix)[0]})
    logging.info(f"Detected subjects: {', '.join(base_subjects)}")

    failed_subjects = []

    for subj in tqdm(base_subjects, desc="Processing subjects"):
        # Find all variants for this subject
        variants = [p for p in subject_folders if parse_subject_suffix(p.name, prefix)[0] == subj]
        logging.debug(f"Subject {subj}: found variants: {[v.name for v in variants]}")

        for var in variants:
            _, suffix = parse_subject_suffix(var.name, prefix)
            session = SUFFIX_SESSION_MAP.get(suffix, "ses-Y0")

            out_subj_dir = ensure_dir(output_dir / f"sub-{subj}")
            out_session_dir = ensure_dir(out_subj_dir / session)

            if not copy_folder(var, out_session_dir, error_log):
                failed_subjects.append(var.name)

    # ---------------- SUMMARY ----------------
    logging.info("BIDS derivative copy complete.")
    if failed_subjects:
        logging.warning(f"{len(failed_subjects)} folders failed to copy. See {error_log} for details:")
        for f in failed_subjects:
            logging.warning(f"  {f}")
    else:
        logging.info("All folders copied successfully.")

# ---------------- CLI ----------------
def main():
    parser = argparse.ArgumentParser(description="Organize derivative outputs into BIDS structure")
    parser.add_argument("--input", required=True, type=str, help="Input folder containing derivative subject folders")
    parser.add_argument("--output", required=True, type=str, help="Output BIDS derivative folder")
    parser.add_argument("--prefix", required=True, type=str, help="Subject folder prefix to replace (e.g., IAM_)")
    args = parser.parse_args()

    input_dir = Path(args.input)
    output_dir = Path(args.output)
    ensure_dir(output_dir)

    logging.basicConfig(
        filename=output_dir / LOG_FILENAME,
        filemode="a",
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s"
    )
    logging.info("Logging initialized.")
    logging.info(f"Input: {input_dir}")
    logging.info(f"Output: {output_dir}")
    logging.info(f"Prefix: {args.prefix}")

    convert_structure(input_dir, output_dir, args.prefix)

if __name__ == "__main__":
    main()

