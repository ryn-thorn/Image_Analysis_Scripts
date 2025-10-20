#!/usr/bin/env python3
"""
Convert mSUVr values to Centiloids using tracer-specific calibration coefficients.

Usage:
  python mSUVr_to_centiloid.py <mSUVr_csv> <output_csv> [--coeff <coefficients.csv>] \
      [--tracer <tracer_name>] [--slope <m>] [--intercept <b>]

Example 1 (use coefficients file):
  python mSUVr_to_centiloid.py my_mSUVr.csv centiloid_out.csv --coeff coefficients.csv --tracer florbetapir

Example 2 (manual coefficients):
  python mSUVr_to_centiloid.py my_mSUVr.csv centiloid_out.csv --slope 63.8 --intercept -81.2
"""

import argparse
import pandas as pd
import sys

def load_coefficients(coeff_file, tracer):
    """Load slope/intercept from coefficients.csv for the given tracer."""
    coeffs = pd.read_csv(coeff_file)
    tracer_row = coeffs[coeffs['tracer'].str.lower() == tracer.lower()]
    if tracer_row.empty:
        sys.exit(f"❌ Tracer '{tracer}' not found in {coeff_file}.")
    m = tracer_row['slope_m'].values[0]
    b = tracer_row['intercept_b'].values[0]
    print(f"✅ Using coefficients for {tracer}: slope={m:.4f}, intercept={b:.4f}")
    return m, b

def main():
    parser = argparse.ArgumentParser(description="Convert mSUVr → Centiloid using calibration coefficients.")
    parser.add_argument("mSUVr_csv", help="Input CSV with mSUVr values (must have column 'mSUVr' or 'mSUVR').")
    parser.add_argument("output_csv", help="Output CSV with Centiloid values added.")
    parser.add_argument("--coeff", help="Optional coefficients CSV (if not supplying slope/intercept manually).")
    parser.add_argument("--tracer", help="Tracer name (used to look up coefficients in --coeff file).")
    parser.add_argument("--slope", type=float, help="Manual slope (override file).")
    parser.add_argument("--intercept", type=float, help="Manual intercept (override file).")
    args = parser.parse_args()

    # --- load mSUVr values ---
    df = pd.read_csv(args.mSUVr_csv)
    col = None
    for c in df.columns:
        if c.lower() in ['msuvr', 'msuvr_', 'suvr']:
            col = c
            break
    if not col:
        sys.exit("❌ Could not find 'mSUVr' column in input file.")

    # --- get coefficients ---
    if args.slope is not None and args.intercept is not None:
        slope, intercept = args.slope, args.intercept
        print(f"✅ Using manual coefficients: slope={slope}, intercept={intercept}")
    elif args.coeff and args.tracer:
        slope, intercept = load_coefficients(args.coeff, args.tracer)
    else:
        sys.exit("❌ Must supply either (--slope and --intercept) OR (--coeff and --tracer).")

    # --- compute centiloids ---
    df['Centiloid'] = slope * df[col] + intercept
    print(f"✅ Calculated Centiloid for {len(df)} subjects.")

    # --- save output ---
    df.to_csv(args.output_csv, index=False)
    print(f"💾 Saved Centiloid values to: {args.output_csv}")

if __name__ == "__main__":
    main()
