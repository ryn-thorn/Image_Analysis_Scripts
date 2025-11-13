#!/usr/bin/env python3
"""
Apply a Centiloid conversion formula (saved from calibration)
to a CSV of Florbetaben SUVRs.

Example:
    python apply_centiloid_formula.py \
        --input my_data.csv \
        --formula /path/to/centiloid_formula.txt \
        --out my_data_centiloid.csv
"""

import argparse
import pandas as pd
import re

def parse_formula(path):
    """Read A and B from centiloid_formula.txt."""
    A, B = None, None
    with open(path, "r") as f:
        for line in f:
            if line.startswith("A"):
                A = float(re.findall(r"[-+]?\d*\.\d+|\d+", line)[0])
            elif line.startswith("B"):
                B = float(re.findall(r"[-+]?\d*\.\d+|\d+", line)[0])
    if A is None or B is None:
        raise ValueError("Could not read A and B from formula file.")
    return A, B

def main(args):
    df = pd.read_csv(args.input)
    A, B = parse_formula(args.formula)

    print(f"Applying Centiloid formula: CL = {A:.4f} * SUVR + {B:.4f}")
    if "msuvr" not in df.columns:
        raise ValueError("Input CSV must have a column named 'msuvr'")

    df["centiloid"] = A * df["msuvr"] + B
    df.to_csv(args.out, index=False)

    print(f"✅ Saved Centiloid results to: {args.out}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="CSV file with 'subject' and 'msuvr'")
    parser.add_argument("--formula", required=True, help="Path to centiloid_formula.txt")
    parser.add_argument("--out", required=True, help="Output CSV path")
    args = parser.parse_args()
    main(args)
