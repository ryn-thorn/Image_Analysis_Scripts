#!/usr/bin/env python

"""
Script to strip Cogstate data and organize in a csv. Output csv will go into input folder.

To use, open terminal and enter the following command:
  python extract_cogstate_scores.py /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Patient_Data/CogState

Requirements:
  pip install pymupdf
"""


import os
import re
import csv
import sys

# ----------------------------
# Dependency check
# ----------------------------
required_modules = ["fitz"]  # PyMuPDF
missing = []
for module in required_modules:
    try:
        __import__(module)
    except ImportError:
        missing.append(module)

if missing:
    print("\n Missing required dependencies:")
    for m in missing:
        if m == "fitz":
            print("   - PyMuPDF (install with: pip install pymupdf)")
        else:
            print(f"   - {m} (install with: pip install {m})")
    sys.exit(1)

import fitz  # noqa: E402


# ----------------------------
# Field list (explicit, fixed order)
# ----------------------------
FIELDNAMES = [
    "SubjID",
    "Detection_Anticipations",
    "Detection_Hits",
    "Detection_Misses",
    "Detection_Score",
    "Detection_Speed",
    "Identification_Accuracy",
    "Identification_Anticipations",
    "Identification_Hits",
    "Identification_Misses",
    "Identification_Score",
    "Identification_Speed",
    "Maze_Errors",
    "One_Back_Accuracy_Accuracy",
    "One_Back_Accuracy_Score",
    "One_Back_Speed_Anticipations",
    "One_Back_Speed_Hits",
    "One_Back_Speed_Misses",
    "One_Back_Speed_Score",
    "One_Back_Speed_Speed",
    "One_Card_Learning_Accuracy",
    "One_Card_Learning_Anticipations",
    "One_Card_Learning_Hits",
    "One_Card_Learning_Misses",
    "One_Card_Learning_Score",
    "One_Card_Learning_Speed",
]


# ----------------------------
# PDF extraction logic
# ----------------------------
def extract_scores_from_pdf(pdf_path):
    """Extract CogState scores (including submetrics) from a PDF and return as dict."""
    with fitz.open(pdf_path) as doc:
        text = ""
        for page in doc:
            text += page.get_text("text")

    subj_match = re.search(r"Subject\s*ID:\s*(\S+)", text)
    subj_id = subj_match.group(1) if subj_match else os.path.basename(pdf_path).split('_tr')[0]

    # Grab "Cognitive Test Results" section — flexible end pattern
    section_match = re.search(r"Cognitive Test Results(.*?)(Result Summary|Please Note|For Cogstate|Note:|This test report)", text, re.S)
    if not section_match:
        print(f"No Cognitive Test Results found in {os.path.basename(pdf_path)}")
        return None

    section = section_match.group(1)

    # Data container
    data = {key: "NA" for key in FIELDNAMES}
    data["SubjID"] = subj_id

    # -------- Detection --------
    detection_block = re.search(r"Detection(.*?)(?=Identification|$)", section, re.S)
    if detection_block:
        block = detection_block.group(1)
        data["Detection_Score"] = _extract_value(r"Detection\s+([0-9NA/.]+)\s*>", section)
        data["Detection_Speed"] = _extract_value(r"Speed\s*\d*\s*([0-9.]+(?:\s*ms)?)", block)
        data["Detection_Hits"] = _extract_value(r"Hits\s*\d*\s*([0-9.]+)", block)
        data["Detection_Misses"] = _extract_value(r"Misses\s*\d*\s*([0-9.]+)", block)
        data["Detection_Anticipations"] = _extract_value(r"Anticipations\s*\d*\s*([0-9.]+)", block)

    # -------- Identification --------
    ident_block = re.search(r"Identification(.*?)(?=One Card Learning|$)", section, re.S)
    if ident_block:
        block = ident_block.group(1)
        data["Identification_Score"] = _extract_value(r"Identification\s+([0-9NA/.]+)\s*>", section)
        data["Identification_Speed"] = _extract_value(r"Speed\s*\d*\s*([0-9.]+(?:\s*ms)?)", block)
        data["Identification_Accuracy"] = _extract_value(r"Accuracy\s*\d*\s*([0-9.]+%)", block)
        data["Identification_Hits"] = _extract_value(r"Hits\s*\d*\s*([0-9.]+)", block)
        data["Identification_Misses"] = _extract_value(r"Misses\s*\d*\s*([0-9.]+)", block)
        data["Identification_Anticipations"] = _extract_value(r"Anticipations\s*\d*\s*([0-9.]+)", block)

    # -------- One Card Learning --------
    ocl_block = re.search(r"One Card Learning(.*?)(?=One Back Speed|$)", section, re.S)
    if ocl_block:
        block = ocl_block.group(1)
        data["One_Card_Learning_Score"] = _extract_value(r"One Card Learning\s+([0-9NA/.]+)\s*>", section)
        data["One_Card_Learning_Speed"] = _extract_value(r"Speed\s*\d*\s*([0-9.]+(?:\s*ms)?)", block)
        data["One_Card_Learning_Accuracy"] = _extract_value(r"Accuracy\s*\d*\s*([0-9.]+%)", block)
        data["One_Card_Learning_Hits"] = _extract_value(r"Hits\s*\d*\s*([0-9.]+)", block)
        data["One_Card_Learning_Misses"] = _extract_value(r"Misses\s*\d*\s*([0-9.]+)", block)
        data["One_Card_Learning_Anticipations"] = _extract_value(r"Anticipations\s*\d*\s*([0-9.]+)", block)

    # -------- One Back Speed --------
    obs_block = re.search(r"One Back Speed(.*?)(?=One Back Accuracy|$)", section, re.S)
    if obs_block:
        block = obs_block.group(1)
        data["One_Back_Speed_Score"] = _extract_value(r"One Back Speed\s+([0-9NA/.]+)\s*>", section)
        data["One_Back_Speed_Speed"] = _extract_value(r"Speed\s*\d*\s*([0-9.]+(?:\s*ms)?)", block)
        data["One_Back_Speed_Hits"] = _extract_value(r"Hits\s*\d*\s*([0-9.]+)", block)
        data["One_Back_Speed_Misses"] = _extract_value(r"Misses\s*\d*\s*([0-9.]+)", block)
        data["One_Back_Speed_Anticipations"] = _extract_value(r"Anticipations\s*\d*\s*([0-9.]+)", block)

    # -------- One Back Accuracy --------
    oba_block = re.search(r"One Back Accuracy(.*?)(?=Maze Errors|$)", section, re.S)
    if oba_block:
        block = oba_block.group(1)
        data["One_Back_Accuracy_Score"] = _extract_value(r"One Back Accuracy\s+([0-9NA/.]+)\s*>", section)
        data["One_Back_Accuracy_Accuracy"] = _extract_value(r"Accuracy\s*\d*\s*([0-9.]+%)", block)

    # -------- Maze Errors --------
    maze_block = re.search(r"Maze Errors(.*?)$", section, re.S)
    if maze_block:
        data["Maze_Errors"] = _extract_value(r"Maze Errors\s+([0-9NA/.]+)\s*>", section)

    return data


def _extract_value(pattern, text):
    """Helper: extract first regex group or return 'NA'."""
    m = re.search(pattern, text)
    return m.group(1).strip() if m else "NA"


# ----------------------------
# Main extraction function
# ----------------------------
def extract_all_scores(input_dir):
    """Find all *_tr.pdf files in input_dir and extract data."""
    output_csv = os.path.join(input_dir, "Cogstate_Summary.csv")
    results = []

    for root, _, files in os.walk(input_dir):
        for f in files:
            if f.endswith("_tr.pdf"):
                pdf_path = os.path.join(root, f)
                scores = extract_scores_from_pdf(pdf_path)
                if scores:
                    results.append(scores)

    if results:
        with open(output_csv, "w", newline="") as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=FIELDNAMES)
            writer.writeheader()
            writer.writerows(results)

        print(f"\n✅ Extraction complete! Output written to: {output_csv} ")
    else:
        print("\n⚠️ No data extracted. Check that input folder or PDF structure are correct.")


# ----------------------------
# CLI entry point
# ----------------------------
if __name__ == "__main__":
    if len(sys.argv) > 1:
        input_folder = sys.argv[1]
    else:
        input_folder = input("Enter the path to the input folder containing *_tr.pdf files: ").strip()

    if not os.path.isdir(input_folder):
        print(f"Invalid directory: {input_folder}")
        sys.exit(1)

    extract_all_scores(input_folder)
