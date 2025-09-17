#!/usr/bin/env python3
import os
import glob
import csv
import argparse

def main(main_folder, out_file):
    rows = []
    skipped = []

    for aseg_path in glob.glob(os.path.join(main_folder, "*", "stats", "aseg.stats")):
        subj_id = os.path.basename(os.path.dirname(os.path.dirname(aseg_path)))  # subject folder
        try:
            with open(aseg_path, "r") as f:
                for line in f:
                    if line.startswith("# Measure EstimatedTotalIntraCranialVol"):
                        parts = line.split(",")
                        eTIV = float(parts[3].strip())
                        rows.append([subj_id, eTIV])
                        break
                else:
                    skipped.append(subj_id)  # aseg.stats exists, but line not found
        except Exception as e:
            skipped.append(subj_id)

    # Write CSV if we got something
    if rows:
        with open(out_file, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["SubjID", "eTIV"])
            writer.writerows(rows)
        print(f"✅ Wrote {len(rows)} subjects to {out_file}")
    else:
        print("⚠️ No aseg.stats files with eTIV found!")

    # Report skipped subjects
    if skipped:
        print(f"⚠️ Skipped {len(skipped)} subjects (missing or malformed aseg.stats):")
        for s in skipped:
            print(f"   - {s}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Extract eTIV from aseg.stats files into a CSV."
    )
    parser.add_argument("main_folder", help="Path to main folder containing subject directories")
    parser.add_argument("out_file", help="Output CSV file path")

    args = parser.parse_args()
    main(args.main_folder, args.out_file)
