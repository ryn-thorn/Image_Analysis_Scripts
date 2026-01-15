#!/usr/bin/env python
"""
PUSH2_BIDS.py — Same script, but with user-supplied paths:
  • --input  : path to ZIP directory
  • --output : path to BIDS output directory
  • --log    : optional log file location (default = <output>/bids_conversion_log.tsv)

No other logic, names, behavior, rules, or code flow changed.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path

import pydicom
from tqdm import tqdm

# ---------------- CONFIG (defaults overridden by CLI) ----------------
INPUT_ZIP_DIR = None
OUTPUT_BIDS_DIR = None
LOG_PATH = None

# Session map
SES_MAP = {
    "": "ses-pretreatment",
    "b": "ses-posttreatment",
}

# Subfolders inside each session
SESSION_SUBFOLDERS = ["anat", "dwi", "fmap", "func", "pet", "mrs", "vista", "other"]

# Series classification rules
CLASS_RULES = [
    (re.compile(r"t1|mprage|spgr", re.I), "anat"),
    (re.compile(r"t2(?![a-z0-9])|t2w|flair", re.I), "anat"),
    (re.compile(r"dki|fbi|diff|dwi|dti", re.I), "dwi"),
    (re.compile(r"task|resting[_-]?state|rest\b|func|bold|fmri|PA", re.I), "func"),
    (re.compile(r"field[_-]?mapping|fmap|phasediff|magnitude|topup|se_epi", re.I), "fmap"),
    (re.compile(r"vista|vista_ref", re.I), "vista"),
]

# ID parsing regex
ID_RE = re.compile(r"[I1]AM[_-]?0*([0-9]+)([A-Za-z]?)")

# BIDS RENAMING RULES
BIDS_NAME_RULES = [
    (re.compile(r"^AAHead_Scout_32ch-head-coil(_.*)?$", re.I), "AAHead_Scout_32ch-head-coil"),
    (re.compile(r"^AAHead_Scout_32ch-head-coila(_.*)?$", re.I), "AAHead_Scout_32ch-head-coil"),
    (re.compile(r"^DKI_30_Dir_i", re.I), "DKI_30dir"),
    (re.compile(r"^DKI_30_Dir_TOP_UP_PA$", re.I), "DKI_30dir_TOPUP"),
    (re.compile(r"^DKI_30_Dir$", re.I), "DKI_30dir"),
    (re.compile(r"^DKI_BIPOLAR_2\.5mm_64dir_50slices_TOP_UP_PA$", re.I), "DKI_64dir_TOPUP"),
    (re.compile(r"^DKI_BIPOLAR_2\.5mm_64dir_50slices$", re.I), "DKI_64dir"),
    (re.compile(r"^DKI_MONOPOLAR_3\.0mm_30dir_42slices_topup", re.I), "DKI_30dir_TOPUP"),
    (re.compile(r"^DKI_MONOPOLAR_3\.0mm_30dir_42slices$", re.I), "DKI_30dir"),
    (re.compile(r"^FBI_", re.I), "FBI"),
    (re.compile(r"^gre_field_mapping_e1$", re.I), "field-map_e1"),
    (re.compile(r"^gre_field_mapping_e2_ph$|^gre_field_mapping_e2$", re.I), "field-map_e2ph"),
    (re.compile(r"^sms3_3\.0iso_PA", re.I), "PA"),
    (re.compile(r"^sms3_3\.0iso_Resting_State_1$", re.I), "Resting_1"),
    (re.compile(r"^sms3_3\.0iso_Resting_State_2_e1$", re.I), "Resting_2_e1"),
    (re.compile(r"^sms3_3\.0iso_Resting_State_2$", re.I), "Resting_2"),
    (re.compile(r"^sms3_3\.0iso_Task$", re.I), "Task"),
    (re.compile(r"^t1_mprage_sag_p2_iso_MPR_Cor$", re.I), "T1w_Cor"),
    (re.compile(r"^t1_mprage_sag_p2_iso_MPR_Tra$", re.I), "T1w_Tra"),
    (re.compile(r"^t1_mprage_sag_p2_iso$", re.I), "T1w"),
    (re.compile(r"^t2_tse_dark-fluid_tra$", re.I), "T2w"),
    (re.compile(r"^t2_tse_dark-fluid_traa$", re.I), "T2wa"),
    (re.compile(r"^t2_tse_dark-fluid_tra_e1$", re.I), "T2w"),
    (re.compile(r"^DKI_30_Dir_e1$", re.I), "DKI_30dir"),
    (re.compile(r"^DKI_30_Dir_TOP_UP_PA_e1$", re.I), "DKI_30dir_TOPUP"),
    (re.compile(r"^DKI_30_Dir_TOP_UP_PA_i00001$", re.I), "DKI_30dir_TOPUP"),
    (re.compile(r"^DKI_BIPOLAR_2\.5mm_64dir_50slices_e1$", re.I), "DKI_64dir"),
    (re.compile(r"^DKI_BIPOLAR_2\.5mm_64dir_50slices_i00001$", re.I), "DKI_64dir"),
    (re.compile(r"^DKI_BIPOLAR_2\.5mm_64dir_50slices_TOP_UP_PA_e1$", re.I), "DKI_64dir_TOPUP"),
    (re.compile(r"^DKI_BIPOLAR_2\.5mm_64dir_50slices_TOP_UP_PA_i00001$", re.I), "DKI_64dir_TOPUP"),
    (re.compile(r"^DKI_BIPOLAR_2\.5mm_64dir_50slices_TOP_UP_PAa$", re.I), "DKI_64dir_TOPUP"),
    (re.compile(r"^DKI_BIPOLAR_2\.5mm_64dir_50slicesa$", re.I), "DKI_64dir"),
    (re.compile(r"^DKI_BIPOLAR_2\.5mm_64dir_50slicesb$", re.I), "DKI_64dir"),
    (re.compile(r"^DKI_MONOPOLAR_3\.0mm_30dir_42slices_e1$", re.I), "DKI_30dir"),
    (re.compile(r"^DKI_MONOPOLAR_3\.0mm_30dir_42slices_i00001$", re.I), "DKI_30dir"),
    (re.compile(r"^gre_field_mapping_e1_i00001$", re.I), "field_map_e1"),
    (re.compile(r"^gre_field_mapping_e1a$", re.I), "field_map_e1"),
    (re.compile(r"^gre_field_mapping_e2_i00001$", re.I), "field_map_e2"),
    (re.compile(r"^gre_field_mapping_e2_pha$", re.I), "field_map_e2"),
    (re.compile(r"^gre_field_mapping_e2a$", re.I), "field_map_e2"),
    (re.compile(r"^gre_field_mapping_i00001_e2_ph$", re.I), "field_map_e2_ph"),
    (re.compile(r"^sms3_3\.0iso_Resting_PA$", re.I), "Resting_1"),
    (re.compile(r"^sms3_3\.0iso_Resting_State_1_e1$", re.I), "Resting_1"),
    (re.compile(r"^sms3_3\.0iso_Resting_State_1_i00001$", re.I), "Resting_1"),
    (re.compile(r"^sms3_3\.0iso_Resting_State_1a$", re.I), "Resting_1"),
    (re.compile(r"^sms3_3\.0iso_Resting_State_2_i00001$", re.I), "Resting_2"),
    (re.compile(r"^sms3_3\.0iso_Task_e1$", re.I), "Task"),
    (re.compile(r"^sms3_3\.0iso_Task_i00001$", re.I), "Task"),
    (re.compile(r"^sms3_3\.0iso_Taska$", re.I), "Task"),
    (re.compile(r"^t1_mprage_sag_p2_iso_e1$", re.I), "T1w"),
    (re.compile(r"^t1_mprage_sag_p2_iso_i00001$", re.I), "T1w"),
    (re.compile(r"^t1_mprage_sag_p2_iso_MPR_Cor_e1$", re.I), "T1w_Cor"),
    (re.compile(r"^t1_mprage_sag_p2_iso_MPR_Cor_i00001$", re.I), "T1w_Cor"),
    (re.compile(r"^t1_mprage_sag_p2_iso_MPR_Cora$", re.I), "T1w_Cor"),
    (re.compile(r"^t1_mprage_sag_p2_iso_MPR_Corb$", re.I), "T1w_Cor"),
    (re.compile(r"^t1_mprage_sag_p2_iso_MPR_Tra_e1$", re.I), "T1w_Tra"),
    (re.compile(r"^t1_mprage_sag_p2_iso_MPR_Tra_i00001$", re.I), "T1w_Tra"),
    (re.compile(r"^t1_mprage_sag_p2_iso_MPR_Traa$", re.I), "T1w_Tra"),
    (re.compile(r"^t1_mprage_sag_p2_iso_MPR_Trab$", re.I), "T1w_Tra"),
    (re.compile(r"^t1_mprage_sag_p2_isoa$", re.I), "T1w"),
    (re.compile(r"^t1_mprage_sag_p2_isob$", re.I), "T1w"),
    (re.compile(r"^t2_tse_dark-fluid_tra_i00001$", re.I), "T2w"),
    (re.compile(r"^t2_tse_dark-fluid_trab$", re.I), "T2w"),
]

# ---------------- Helpers ----------------
def write_log_row(ts, zipname, raw_pid, normalized_subject, session, outpath, status, note=""):
    header = "timestamp\tzipfile\tpatient_id\tnormalized_subject\tsession\toutpath\tstatus\tnote\n"
    write_header = not LOG_PATH.exists()
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(LOG_PATH, "a") as f:
        if write_header:
            f.write(header)
        row = f"{ts}\t{zipname}\t{raw_pid or ''}\t{normalized_subject or ''}\t{session or ''}\t{outpath or ''}\t{status}\t{note}\n"
        f.write(row)

def parse_patient_id(pid_raw):
    if not pid_raw:
        return None, None, None
    m = ID_RE.search(pid_raw.strip())
    if m:
        num = m.group(1).lstrip("0") or "0"
        suffix = m.group(2) or ""
        if suffix.upper() == "A":
            return f"sub-{num}A", "A", num
        if suffix.lower() in ("b", "c", "d"):
            return f"sub-{num}", suffix.lower(), num
        if suffix == "":
            return f"sub-{num}", "", num
        return f"sub-{num}{suffix}", suffix, num
    m2 = re.search(r"([0-9]{3,})", pid_raw)
    if m2:
        num = m2.group(1).lstrip("0") or "0"
        return f"sub-{num}", "", num
    return None, None, None

def find_dicom_root(extract_dir: Path):
    for p in extract_dir.rglob("*"):
        if p.is_dir() and p.name.lower() == "dicom":
            return p
    candidates = []
    for p in extract_dir.iterdir():
        if p.is_dir():
            nfiles = sum(1 for _ in p.rglob("*") if _.is_file())
            candidates.append((nfiles, p))
    if candidates:
        candidates.sort(reverse=True)
        if candidates[0][0] > 0:
            return candidates[0][1]
    return extract_dir

def find_first_valid_dicom(dicom_dir: Path):
    for p in dicom_dir.rglob("*"):
        if p.is_file():
            try:
                ds = pydicom.dcmread(str(p), stop_before_pixels=True, force=True)
                if getattr(ds, "PatientID", None) or getattr(ds, "SeriesDescription", None) or getattr(ds, "ProtocolName", None):
                    return p
            except Exception:
                continue
    return None

def choose_session_from_suffix(suffix):
    return SES_MAP.get(suffix, "ses-Y0")

def classify_series_name(name):
    if not name:
        return "other"
    for pat, tgt in CLASS_RULES:
        if pat.search(name):
            return tgt
    return "other"

def run_dcm2niix(dicom_dir: Path, out_dir: Path, compress=True):
    out_dir.mkdir(parents=True, exist_ok=True)
    zflag = "y" if compress else "n"
    cmd = [
        "dcm2niix",
        "-z", zflag,
        "-o", str(out_dir),
        "-f", "%p",
        str(dicom_dir)
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        return proc.returncode, proc.stdout + proc.stderr
    except FileNotFoundError as e:
        return 127, str(e)

def apply_bids_rename(fpath: Path, subject: str, session: str):
    name = fpath.name
    if name.lower().endswith('.nii.gz'):
        true_stem = name[:-7]
        ext = '.nii.gz'
    else:
        true_stem = fpath.stem
        ext = fpath.suffix

    for pat, bids_suffix in BIDS_NAME_RULES:
        if pat.match(true_stem):
            new_base = f"{subject}_{session}_{bids_suffix}"
            new_name = new_base + ext
            new_path = fpath.with_name(new_name)
            if new_path.exists():
                i = 1
                while True:
                    alt = fpath.with_name(f"{new_base}_dup{i}{ext}")
                    if not alt.exists():
                        new_path = alt
                        break
                    i += 1
            try:
                fpath.rename(new_path)
                return True, new_path, f"RENAMED:{name}=>{new_path.name}"
            except Exception as e:
                return False, fpath, f"RENAME_FAILED:{e}"

    return False, fpath, "NO_RENAME_RULE_MATCH"

# ---------------- Main zip processing ----------------
def process_zip(zip_path: Path, overwrite=False, dry_run=False):
    ts = datetime.utcnow().isoformat()
    zipname = zip_path.name
    tmp_extract = Path(tempfile.mkdtemp(prefix="iam_unzip_"))
    status = "ERROR"
    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            zf.extractall(tmp_extract)

        dicom_root = find_dicom_root(tmp_extract)
        if dicom_root is None or not any(p.is_file() for p in dicom_root.rglob("*")):
            status = "NO_DICOM_FOUND"
            write_log_row(ts, zipname, "", "", "", "", status, "no files in dicom root")
            return

        first_dcm = find_first_valid_dicom(dicom_root)
        if first_dcm is None:
            status = "NO_VALID_DICOM"
            write_log_row(ts, zipname, "", "", "", "", status, "no readable dicom found")
            return

        try:
            ds = pydicom.dcmread(str(first_dcm), stop_before_pixels=True, force=True)
        except Exception as e:
            status = "DICOM_READ_FAIL"
            write_log_row(ts, zipname, "", "", "", "", status, str(e))
            return

        raw_pid = str(getattr(ds, "PatientID", "") or "")
        normalized_subj, suffix, numeric = parse_patient_id(raw_pid)
        if not normalized_subj:
            normalized_subj, suffix, numeric = parse_patient_id(zip_path.stem)
        if not normalized_subj:
            status = "BAD_PATIENT_ID"
            write_log_row(ts, zipname, raw_pid, "", "", "", status, "could not parse ID")
            return

        session = choose_session_from_suffix(suffix or "")
        subj_folder = OUTPUT_BIDS_DIR / normalized_subj
        session_dir = subj_folder / session

        for sf in ["ses-Y0", "ses-Y2", "ses-Y4", "ses-Y6"]:
            for ssub in SESSION_SUBFOLDERS:
                (subj_folder / sf / ssub).mkdir(parents=True, exist_ok=True)

        DATA_EXTS = {".nii", ".gz", ".json", ".bval", ".bvec", ".tsv"}

        target_session_has_files = any(
            p.is_file() and (p.suffix.lower() in DATA_EXTS or p.name.lower().endswith('.nii.gz'))
            for p in session_dir.rglob("*")
        )

        if target_session_has_files and not overwrite:
            status = "SKIPPED_SESSION_EXISTS"
            write_log_row(ts, zipname, raw_pid, normalized_subj, session,
                          str(session_dir), status, "session contains data files; use --overwrite")
            return

        if dry_run:
            status = "DRY_RUN_OK"
            write_log_row(ts, zipname, raw_pid, normalized_subj, session, str(session_dir), status, "dry-run")
            return

        if overwrite and target_session_has_files:
            shutil.rmtree(session_dir)
            for ssub in SESSION_SUBFOLDERS:
                (session_dir / ssub).mkdir(parents=True, exist_ok=True)

        dcm2niix_out = Path(tempfile.mkdtemp(prefix="iam_dcm2niix_"))
        code, dcm2txt = run_dcm2niix(dicom_root, dcm2niix_out, compress=True)
        if code != 0:
            status = f"DCM2NIIX_FAILURE_{code}"
            write_log_row(ts, zipname, raw_pid, normalized_subj, session,
                          str(dcm2niix_out), status, dcm2txt.strip())
            return

        produced = sorted([p for p in dcm2niix_out.iterdir() if p.is_file()])
        if not produced:
            status = "DCM2NIIX_NO_OUTPUT"
            write_log_row(ts, zipname, raw_pid, normalized_subj, session,
                          str(dcm2niix_out), status, dcm2txt.strip())
            return

        files_by_base = {}
        for p in produced:
            basekey = re.sub(r"\.nii(\.gz)?$|\.json$|\.bval$|\.bvec$", "", p.name, flags=re.I)
            files_by_base.setdefault(basekey, []).append(p)

        moved_any = False
        for basekey, files in files_by_base.items():
            series_desc = None
            json_file = next((p for p in files if p.suffix.lower() == ".json"), None)
            if json_file:
                try:
                    j = json.loads(json_file.read_text())
                    series_desc = (
                        j.get("SeriesDescription")
                        or j.get("series_description")
                        or j.get("ProtocolName")
                        or j.get("SeriesDescriptionInternal")
                    )
                except Exception:
                    series_desc = None
            if not series_desc:
                series_desc = basekey

            target_subfolder_name = classify_series_name(series_desc)
            final_target = session_dir / target_subfolder_name
            final_target.mkdir(parents=True, exist_ok=True)

            for f in files:
                dest = final_target / f.name
                if dest.exists():
                    dest = final_target / (f.stem + "_dup" + f.suffix)
                shutil.move(str(f), str(dest))

                renamed, new_path, note = apply_bids_rename(dest, normalized_subj, session)
                if renamed:
                    write_log_row(datetime.utcnow().isoformat(), zipname, raw_pid,
                                  normalized_subj, session, str(new_path), "RENAMED", note)
                else:
                    write_log_row(datetime.utcnow().isoformat(), zipname, raw_pid,
                                  normalized_subj, session, str(dest), "NO_RENAME_RULE_MATCH", note)

                moved_any = True

        try:
            if dcm2niix_out.exists():
                shutil.rmtree(dcm2niix_out)
        except Exception:
            pass

        if moved_any:
            status = "OK"
            write_log_row(ts, zipname, raw_pid, normalized_subj, session,
                          str(session_dir), status,
                          dcm2txt.strip().splitlines()[-1] if dcm2txt else "")
        else:
            status = "NO_MOVED_FILES"
            write_log_row(ts, zipname, raw_pid, normalized_subj, session,
                          str(session_dir), status, "no moved files")

    except Exception as e:
        status = "EXCEPTION"
        write_log_row(ts, zipname, "", "", "", "", status, repr(e))
    finally:
        try:
            shutil.rmtree(tmp_extract)
        except Exception:
            pass

# ---------------- CLI & Runner ----------------
def main():
    global INPUT_ZIP_DIR, OUTPUT_BIDS_DIR, LOG_PATH

    parser = argparse.ArgumentParser(
        description="Organize IAM zipped dicoms into BIDS-like layout with renaming"
    )
    parser.add_argument("--input", required=True, help="Directory containing .zip files")
    parser.add_argument("--output", required=True, help="Output BIDS directory")
    parser.add_argument("--log", help="Override log file path")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing session data.")
    parser.add_argument("--dry-run", action="store_true", help="Parse + extract only, no dcm2niix.")

    args = parser.parse_args()

    INPUT_ZIP_DIR = Path(args.input)
    OUTPUT_BIDS_DIR = Path(args.output)
    LOG_PATH = Path(args.log) if args.log else OUTPUT_BIDS_DIR / "bids_conversion_log.tsv"

    if not INPUT_ZIP_DIR.exists():
        print("Input zip dir not found:", INPUT_ZIP_DIR)
        sys.exit(1)
    OUTPUT_BIDS_DIR.mkdir(parents=True, exist_ok=True)

    try:
        subprocess.run(["dcm2niix", "-h"], capture_output=True, check=False)
    except FileNotFoundError:
        print("dcm2niix not found in PATH.")
        sys.exit(1)

    zip_files = sorted([p for p in INPUT_ZIP_DIR.iterdir()
                        if p.is_file() and p.suffix.lower() == ".zip"])
    if not zip_files:
        print("No zip files found in", INPUT_ZIP_DIR)
        sys.exit(0)

    print(f"Found {len(zip_files)} zip files in {INPUT_ZIP_DIR}")
    for z in tqdm(zip_files):
        print("Processing:", z.name)
        process_zip(z, overwrite=args.overwrite, dry_run=args.dry_run)

if __name__ == "__main__":
    main()
