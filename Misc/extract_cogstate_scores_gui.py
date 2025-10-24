#!/usr/bin/env python3
"""
GUI version of CogState extractor — no command-line needed.
Lets user select a folder of *_tr.pdf files and outputs Cogstate_Summary.csv.
"""

import os
import re
import csv
import sys
import tkinter as tk
from tkinter import filedialog, messagebox

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
    msg = "Missing required packages:\n\n"
    for m in missing:
        if m == "fitz":
            msg += "• PyMuPDF (install with: pip install pymupdf)\n"
        else:
            msg += f"• {m} (install with: pip install {m})\n"
    messagebox.showerror("Missing Dependencies", msg)
    sys.exit(1)

import fitz  # noqa: E402

# ----------------------------
# Field list (fixed order)
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
# Extraction functions
# ----------------------------
def _extract_value(pattern, text):
    m = re.search(pattern, text)
    return m.group(1).strip() if m else "NA"


def extract_scores_from_pdf(pdf_path):
    with fitz.open(pdf_path) as doc:
        text = "".join(page.get_text("text") for page in doc)

    subj_match = re.search(r"Subject\s*ID:\s*(\S+)", text)
    subj_id = subj_match.group(1) if subj_match else os.path.basename(pdf_path).split("_tr")[0]

    section_match = re.search(
        r"Cognitive Test Results(.*?)(Result Summary|Please Note|For Cogstate|Note:|This test report)",
        text,
        re.S,
    )
    if not section_match:
        print(f"⚠️ No Cognitive Test Results found in {os.path.basename(pdf_path)}")
        return None

    section = section_match.group(1)
    data = {key: "NA" for key in FIELDNAMES}
    data["SubjID"] = subj_id

    # Each test block
    blocks = {
        "Detection": r"Detection(.*?)(?=Identification|$)",
        "Identification": r"Identification(.*?)(?=One Card Learning|$)",
        "One_Card_Learning": r"One Card Learning(.*?)(?=One Back Speed|$)",
        "One_Back_Speed": r"One Back Speed(.*?)(?=One Back Accuracy|$)",
        "One_Back_Accuracy": r"One Back Accuracy(.*?)(?=Maze Errors|$)",
        "Maze_Errors": r"Maze Errors(.*?)$",
    }

    # Detection
    det = re.search(blocks["Detection"], section, re.S)
    if det:
        b = det.group(1)
        data["Detection_Score"] = _extract_value(r"Detection\s+([0-9NA/.]+)\s*>", section)
        data["Detection_Speed"] = _extract_value(r"Speed\s*\d*\s*([0-9.]+(?:\s*ms)?)", b)
        data["Detection_Hits"] = _extract_value(r"Hits\s*\d*\s*([0-9.]+)", b)
        data["Detection_Misses"] = _extract_value(r"Misses\s*\d*\s*([0-9.]+)", b)
        data["Detection_Anticipations"] = _extract_value(r"Anticipations\s*\d*\s*([0-9.]+)", b)

    # Identification
    ident = re.search(blocks["Identification"], section, re.S)
    if ident:
        b = ident.group(1)
        data["Identification_Score"] = _extract_value(r"Identification\s+([0-9NA/.]+)\s*>", section)
        data["Identification_Speed"] = _extract_value(r"Speed\s*\d*\s*([0-9.]+(?:\s*ms)?)", b)
        data["Identification_Accuracy"] = _extract_value(r"Accuracy\s*\d*\s*([0-9.]+%)", b)
        data["Identification_Hits"] = _extract_value(r"Hits\s*\d*\s*([0-9.]+)", b)
        data["Identification_Misses"] = _extract_value(r"Misses\s*\d*\s*([0-9.]+)", b)
        data["Identification_Anticipations"] = _extract_value(r"Anticipations\s*\d*\s*([0-9.]+)", b)

    # One Card Learning
    ocl = re.search(blocks["One_Card_Learning"], section, re.S)
    if ocl:
        b = ocl.group(1)
        data["One_Card_Learning_Score"] = _extract_value(r"One Card Learning\s+([0-9NA/.]+)\s*>", section)
        data["One_Card_Learning_Speed"] = _extract_value(r"Speed\s*\d*\s*([0-9.]+(?:\s*ms)?)", b)
        data["One_Card_Learning_Accuracy"] = _extract_value(r"Accuracy\s*\d*\s*([0-9.]+%)", b)
        data["One_Card_Learning_Hits"] = _extract_value(r"Hits\s*\d*\s*([0-9.]+)", b)
        data["One_Card_Learning_Misses"] = _extract_value(r"Misses\s*\d*\s*([0-9.]+)", b)
        data["One_Card_Learning_Anticipations"] = _extract_value(r"Anticipations\s*\d*\s*([0-9.]+)", b)

    # One Back Speed
    obs = re.search(blocks["One_Back_Speed"], section, re.S)
    if obs:
        b = obs.group(1)
        data["One_Back_Speed_Score"] = _extract_value(r"One Back Speed\s+([0-9NA/.]+)\s*>", section)
        data["One_Back_Speed_Speed"] = _extract_value(r"Speed\s*\d*\s*([0-9.]+(?:\s*ms)?)", b)
        data["One_Back_Speed_Hits"] = _extract_value(r"Hits\s*\d*\s*([0-9.]+)", b)
        data["One_Back_Speed_Misses"] = _extract_value(r"Misses\s*\d*\s*([0-9.]+)", b)
        data["One_Back_Speed_Anticipations"] = _extract_value(r"Anticipations\s*\d*\s*([0-9.]+)", b)

    # One Back Accuracy
    oba = re.search(blocks["One_Back_Accuracy"], section, re.S)
    if oba:
        b = oba.group(1)
        data["One_Back_Accuracy_Score"] = _extract_value(r"One Back Accuracy\s+([0-9NA/.]+)\s*>", section)
        data["One_Back_Accuracy_Accuracy"] = _extract_value(r"Accuracy\s*\d*\s*([0-9.]+%)", b)

    # Maze Errors
    data["Maze_Errors"] = _extract_value(r"Maze Errors\s+([0-9NA/.]+)\s*>", section)

    return data


def extract_all_scores(input_dir):
    results = []
    for root, _, files in os.walk(input_dir):
        for f in files:
            if f.endswith("_tr.pdf"):
                pdf_path = os.path.join(root, f)
                scores = extract_scores_from_pdf(pdf_path)
                if scores:
                    results.append(scores)

    output_csv = os.path.join(input_dir, "Cogstate_Summary.csv")
    if results:
        with open(output_csv, "w", newline="") as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=FIELDNAMES)
            writer.writeheader()
            writer.writerows(results)
        return output_csv, len(results)
    return None, 0


# ----------------------------
# GUI
# ----------------------------
def run_gui():
    root = tk.Tk()
    root.title("CogState PDF Extractor")
    root.geometry("420x240")
    root.resizable(False, False)

    label = tk.Label(root, text="Select the folder containing your *_tr.pdf files:", pady=10)
    label.pack()

    path_var = tk.StringVar()

    entry = tk.Entry(root, textvariable=path_var, width=50)
    entry.pack(padx=10, pady=5)

    def browse():
        folder = filedialog.askdirectory()
        if folder:
            path_var.set(folder)

    browse_btn = tk.Button(root, text="Browse...", command=browse)
    browse_btn.pack(pady=5)

    output_label = tk.Label(root, text="", fg="gray")
    output_label.pack(pady=10)

    def run_extraction():
        folder = path_var.get().strip()
        if not folder or not os.path.isdir(folder):
            messagebox.showerror("Error", "Please select a valid input folder.")
            return

        output_label.config(text="Extracting data... please wait.", fg="blue")
        root.update_idletasks()

        csv_path, count = extract_all_scores(folder)

        if csv_path and count > 0:
            messagebox.showinfo(
                "Extraction Complete",
                f"Successfully extracted {count} records.\n\nSaved to:\n{csv_path}",
            )
            output_label.config(text="✅ Extraction complete.", fg="green")
        else:
            messagebox.showwarning("No Data Found", "No valid CogState test results were extracted.")
            output_label.config(text="⚠️ No data extracted.", fg="red")

    run_btn = tk.Button(root, text="Run Extraction", command=run_extraction, width=20, bg="#007acc", fg="white")
    run_btn.pack(pady=10)

    quit_btn = tk.Button(root, text="Quit", command=root.destroy)
    quit_btn.pack(pady=5)

    root.mainloop()


if __name__ == "__main__":
    run_gui()
