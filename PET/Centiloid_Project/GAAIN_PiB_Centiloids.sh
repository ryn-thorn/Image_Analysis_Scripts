#!/usr/bin/env bash
set -euo pipefail

# GAAIN_PiB_Centiloids.sh

#/Volumes/vdrive/helpern_share/Image_Analysis_Scripts/PET/Centiloid_Project/GAAIN_PiB_Centiloids.sh --voi /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/Centiloid_Std_VOI/nifti/2mm --yc_pet /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/Calibrated-Coefficients/GAAIN_PiB_Scans/YC-0_PET_5070/nifti --yc_mr /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/Calibrated-Coefficients/GAAIN_PiB_Scans/YC-0_MR/nifti --ad_pet /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/Calibrated-Coefficients/GAAIN_PiB_Scans/AD-100_PET_5070/nifti --ad_mr /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/Calibrated-Coefficients/GAAIN_PiB_Scans/AD-100_MR/nifti --out /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/Calibrated-Coefficients/Calibration --threads 4 --paired_csv /Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/Calibrated-Coefficients/both_tracers.csv


# Extends the FSL pipeline to also compute Centiloids.
# - Runs FSL registration pipeline (PiB or other tracer PETs)
# - Produces centiloid_suvr.csv (per-subject SUVR)
# - Computes YC-0 / AD-100 means and QC vs published anchors
# - If provided, fits tracer->PiB linear regression from --paired_csv
# - Converts tracer SUVRs to PiB-equivalent and then to Centiloids
#
# REQUIREMENTS:
# - FSL in PATH
# - GNU parallel
# - Python 3 with numpy, pandas, matplotlib (for regression/plot)
#
# USAGE:
# ./GAAIN_PiB_Centiloids.sh \
#   --voi /path/VOIs \
#   --yc_pet /path/YC0_PET \
#   --yc_mr /path/YC0_MR \
#   --ad_pet /path/AD100_PET \
#   --ad_mr /path/AD100_MR \
#   --out /path/out \
#   --threads 6 \
#   [--paired_csv /path/paired.csv] \
#   [--to_convert_csv /path/to_convert.csv]
#
# paired.csv columns: subject,tracer_suvr,pib_suvr  (header line optional)
# to_convert.csv columns: subject,tracer_suvr

print_usage(){
  cat <<EOF
Usage: $0 --voi VOI_DIR --yc_pet YC_PET_DIR --yc_mr YC_MR_DIR --ad_pet AD_PET_DIR --ad_mr AD_MR_DIR --out OUT_DIR [--threads N] [--paired_csv PAIRED_CSV] [--to_convert_csv TO_CONVERT_CSV]

See inline help in the script for details.
EOF
}

# ---- Arguments (same as before plus two new optional CSVs) ----
VOI_DIR=""
YC_PET=""
YC_MR=""
AD_PET=""
AD_MR=""
OUT_DIR=""
THREADS=4
PAIRED_CSV=""
TO_CONVERT_CSV=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --voi) VOI_DIR="$2"; shift 2;;
    --yc_pet) YC_PET="$2"; shift 2;;
    --yc_mr) YC_MR="$2"; shift 2;;
    --ad_pet) AD_PET="$2"; shift 2;;
    --ad_mr) AD_MR="$2"; shift 2;;
    --out) OUT_DIR="$2"; shift 2;;
    --threads) THREADS="$2"; shift 2;;
    --paired_csv) PAIRED_CSV="$2"; shift 2;;
    --to_convert_csv) TO_CONVERT_CSV="$2"; shift 2;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "Unknown arg: $1"; print_usage; exit 1 ;;
  esac
done

if [[ -z "$VOI_DIR" || -z "$YC_PET" || -z "$YC_MR" || -z "$AD_PET" || -z "$AD_MR" || -z "$OUT_DIR" ]]; then
  echo "Missing required argument."
  print_usage
  exit 1
fi

for cmd in flirt parallel python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd"
    exit 1
  fi
done

mkdir -p "$OUT_DIR"/{csv,logs,qc_pngs,work,rows,regression}

VOI_CORTEX="$VOI_DIR/voi_ctx_2mm.nii"
VOI_CEREB="$VOI_DIR/voi_WhlCblBrnStm_2mm.nii"

for f in "$VOI_CORTEX" "$VOI_CEREB"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: VOI file not found: $f"
    exit 1
  fi
done

MNI_T1="$FSLDIR/data/standard/MNI152_T1_2mm.nii.gz"
MNI_T1_BRAIN="$FSLDIR/data/standard/MNI152_T1_2mm_brain.nii.gz"
if [[ ! -f "$MNI_T1" || ! -f "$MNI_T1_BRAIN" ]]; then
  echo "ERROR: Cannot find MNI template in FSLDIR: $MNI_T1"
  exit 1
fi

# Embedded published anchor values from Klunk et al. (2015) for QC
PUBLISHED_YC0_SUVR=1.009
PUBLISHED_AD100_SUVR=2.087
QC_THRESHOLD_PERCENT=2.0   # +/- 2% threshold

# Prepare subject list (same helper as earlier)
SUBJECT_LIST="$OUT_DIR/work/subjects.tsv"
: > "$SUBJECT_LIST"

prepare_subjects() {
  local petdir="$1"; local mrdir="$2"; local group="$3"; local out_list="$4"
  find "$petdir" -maxdepth 1 -type f \( -iname "*.nii" -o -iname "*.nii.gz" \) | while read -r petf; do
    base=$(basename "$petf")
    if [[ -f "$mrdir/$base" ]]; then
      echo -e "${group}\t${petdir}\t${mrdir}\t${base}" >> "$out_list"
    else
      if [[ "$base" == *.nii.gz ]]; then
        alt="${base%.nii.gz}.nii"
      elif [[ "$base" == *.nii ]]; then
        alt="${base%.nii}.nii.gz"
      else
        alt="$base"
      fi
      if [[ -f "$mrdir/$alt" ]]; then
        echo -e "${group}\t${petdir}\t${mrdir}\t${base}" >> "$out_list"
      else
        echo "WARNING: No matching MR for PET $petf in $mrdir -- skipping" >&2
      fi
    fi
  done
}

prepare_subjects "$YC_PET" "$YC_MR" "YC-0" "$SUBJECT_LIST"
prepare_subjects "$AD_PET" "$AD_MR" "AD-100" "$SUBJECT_LIST"

if [[ ! -s "$SUBJECT_LIST" ]]; then
  echo "ERROR: No matched subjects found. Check directories and filenames."
  exit 1
fi

# Worker function (unchanged from previous version)
process_subject(){
  group="$1"; petdir="$2"; mrdir="$3"; base="$4"; outdir="$5"
  subjname="${base%%.*}"
  logf="$outdir/logs/${subjname}.log"
  workd="$outdir/work/${subjname}"
  rowf="$outdir/rows/${subjname}.row"
  mkdir -p "$workd"

  {
  set -x
  PET_IN="$petdir/$base"
  MR_IN="$mrdir/$base"

  fslreorient2std "$PET_IN" "$workd/${subjname}_pet_reor.nii.gz"
  fslreorient2std "$MR_IN" "$workd/${subjname}_mr_reor.nii.gz"

  MR_reor="$workd/${subjname}_mr_reor.nii.gz"
  PET_reor="$workd/${subjname}_pet_reor.nii.gz"
  
  echo "DEBUG: MRPATH='$mrpath'"

  MR_brain="$workd/${subjname}_mr_brain.nii.gz"
	if ! bet "$MR_reor" "$MR_brain" -R -f 0.3 -g 0 2>/tmp/bet_warn.log; then
	  # Check if output still exists (sometimes bet "fails" but writes a valid file)
	  if [ -f "$MR_brain" ]; then
		echo "⚠️  BET reported an error but produced output; continuing anyway."
	  else
		echo "❌ BET truly failed — no output created. Stopping."
		cat /tmp/bet_warn.log
		exit 1
	  fi
	fi

  AFFINE="$workd/${subjname}_mr2mni_affine.mat"
  flirt -in "$MR_brain" -ref "$MNI_T1_BRAIN" -out "$workd/${subjname}_mr2mni_affine.nii.gz" -omat "$AFFINE" -dof 12
  FNIRT_WARP="$workd/${subjname}_mr2mni_warpfield.nii.gz"
  fnirt --in="$MR_reor" --aff="$AFFINE" --ref="$MNI_T1" --cout="$FNIRT_WARP" --iout="$workd/${subjname}_mr2mni_warped.nii.gz" || FNIRT_WARP=""

  PET2MR_AFF="$workd/${subjname}_pet2mr.mat"
  PET_in_mr="$workd/${subjname}_pet_in_mr.nii.gz"
  flirt -in "$PET_reor" -ref "$MR_brain" -out "$PET_in_mr" -omat "$PET2MR_AFF" -dof 6 -cost mutualinfo

  PET_in_mni="$workd/${subjname}_pet_in_mni.nii.gz"
  if [[ -n "$FNIRT_WARP" && -f "$FNIRT_WARP" ]]; then
    applywarp --in="$PET_reor" --ref="$MNI_T1" --warp="$FNIRT_WARP" --premat="$PET2MR_AFF" --out="$PET_in_mni"
  else
    COMB_AFF="$workd/${subjname}_pet2mni_affine.mat"
    convert_xfm -omat "$COMB_AFF" -concat "$AFFINE" "$PET2MR_AFF"
    flirt -in "$PET_reor" -ref "$MNI_T1" -out "$PET_in_mni" -init "$COMB_AFF" -applyxfm
  fi

  PET_in_mni_resamp="$workd/${subjname}_pet_in_mni_2mm.nii.gz"
  flirt -in "$PET_in_mni" -ref "$MNI_T1" -out "$PET_in_mni_resamp" -interp trilinear

  mean_cortex=$(fslstats "$PET_in_mni_resamp" -k "$VOI_CORTEX" -M 2>/dev/null || echo "NA")
  mean_cereb=$(fslstats "$PET_in_mni_resamp" -k "$VOI_CEREB" -M 2>/dev/null || echo "NA")
  if [[ -z "$mean_cortex" ]]; then mean_cortex="NA"; fi
  if [[ -z "$mean_cereb" ]]; then mean_cereb="NA"; fi

  if [[ "$mean_cereb" == "NA" || "$mean_cereb" == "0" ]]; then
    suvr="NA"
  else
    suvr=$(awk -v a="$mean_cortex" -v b="$mean_cereb" 'BEGIN{ if(b==0 || a=="NA" || b=="NA") {print "NA"} else {printf("%.6f", a/b)} }')
  fi

  PNG="$outdir/qc_pngs/${subjname}_pet_mni_slice.png"
  slicer "$PET_in_mni_resamp" -s 150 -a 0 -x 128 -y 128 -z 64 "$PNG" || true

  printf "%s,%s,%s,%s,%s\n" "$group" "$subjname" "$mean_cortex" "$mean_cereb" "$suvr" > "$rowf"

  set +x
  } > "$logf" 2>&1 || {
    echo "Subject $subjname FAILED. See log: $logf"
  }
}

export -f process_subject
export VOI_CORTEX VOI_CEREB MNI_T1 MNI_T1_BRAIN

# Run in parallel
# ---- PATCHED: use -a and direct function call to avoid fragile quoting that caused EOF errors ----
parallel -a "$SUBJECT_LIST" -j "$THREADS" --colsep '\t' \
  process_subject {1} {2} {3} {4} "$OUT_DIR"

# Combine per-subject row files into final CSV
CSV_OUT="$OUT_DIR/csv/centiloid_suvr.csv"
echo "group,subject,mean_cortex,mean_cerebellum,SUVr" > "$CSV_OUT"
find "$OUT_DIR/rows" -type f -name "*.row" -print0 | sort -z | xargs -0 -r cat >> "$CSV_OUT"
echo "Saved per-subject SUVR CSV: $CSV_OUT"

# ---- Compute group-level N, mean, SD (same logic as before) ----
GROUP_SUM="$OUT_DIR/group_summary.txt"
: > "$GROUP_SUM"

compute_stats_for_group() {
  group="$1"
  awk -F, -v grp="$group" '
    BEGIN { n=0; sum=0; sumsq=0 }
    NR>1 && $1==grp {
      val = $5
      if (val != "NA" && val+0 == val) {
        n++
        sum += val
        sumsq += (val*val)
      }
    }
    END {
      if (n==0) {
        print grp",N=0,mean=NA,sd=NA"
      } else if (n==1) {
        mean = sum/n
        print grp",N="n",mean="mean",sd=NA"
      } else {
        mean = sum/n
        sd = sqrt((sumsq - n*mean*mean)/(n-1))
        printf("%s,N=%d,mean=%.6f,sd=%.6f\n", grp, n, mean, sd)
      }
    }' "$CSV_OUT"
}

yc_line=$(compute_stats_for_group "YC-0")
ad_line=$(compute_stats_for_group "AD-100")

parse_line_get(){ echo "$1" | awk -F'[=,]' '{ for(i=1;i<=NF;i++){ if($i=="mean") {print $(i+1); exit} } }'; }
parse_line_get_n(){ echo "$1" | awk -F'[=,]' '{ for(i=1;i<=NF;i++){ if($i=="N") {print $(i+1); exit} } }'; }
parse_line_get_sd(){ echo "$1" | awk -F'[=,]' '{ for(i=1;i<=NF;i++){ if($i=="sd") {print $(i+1); exit} } }'; }

yc_N=$(parse_line_get_n "$yc_line")
yc_mean=$(parse_line_get "$yc_line")
yc_sd=$(parse_line_get_sd "$yc_line")
ad_N=$(parse_line_get_n "$ad_line")
ad_mean=$(parse_line_get "$ad_line")
ad_sd=$(parse_line_get_sd "$ad_line")

# ---- Write group summary and QC vs published anchors ----
{
  echo "Centiloid pipeline group summary"
  echo "Published anchors (Klunk et al. 2015): YC-0 (PiB mean) = $PUBLISHED_YC0_SUVR   AD-100 (PiB mean) = $PUBLISHED_AD100_SUVR"
  echo ""
  echo "YC-0: $yc_line"
  echo "AD-100: $ad_line"
  echo ""
  # qc function inline
  compute_qc_inline() {
    grp="$1"; meanv="$2"; pub="$3"
    if [[ "$meanv" == "NA" || -z "$meanv" ]]; then
      echo "$grp: mean=NA -> QC=FAIL (no valid subjects)"
      return
    fi
    perc=$(awk -v a="$meanv" -v b="$pub" 'BEGIN{printf("%.3f", 100*(a-b)/b)}')
    absperc=$(awk -v p="$perc" 'BEGIN{if(p<0) p=-p; printf("%.3f", p)}')
    pass="FAIL"
    cmp=$(awk -v p="$absperc" -v t="$QC_THRESHOLD_PERCENT" 'BEGIN{print(p<=t?1:0)}')
    if [[ "$cmp" -eq 1 ]]; then pass="PASS"; fi
    echo "$grp: mean=$meanv  published=$pub  %diff=$perc%  abs%=$absperc%  QC=$pass"
  }
  compute_qc_inline "YC-0" "$yc_mean" "$PUBLISHED_YC0_SUVR"
  compute_qc_inline "AD-100" "$ad_mean" "$PUBLISHED_AD100_SUVR"
} | tee "$GROUP_SUM"

echo "Group summary written to: $GROUP_SUM"

# ---- CENTILOID CONVERSION ----
# We will use the computed anchor means (yc_mean and ad_mean) as the numerator/denominator for conversion.
# If user provided a paired CSV, fit PiB = a + b * tracer and use it to convert tracer_suvr -> PiB_CalcSUVr -> Centiloid.
# If user didn't provide paired CSV but provided a to_convert CSV with measured PiB, we convert PiB directly.
# If neither provided, we only provide message and stop.

CONVERT_OUT="$OUT_DIR/csv/centiloid_converted.csv"
REG_DIR="$OUT_DIR/regression"
mkdir -p "$REG_DIR"

# function to compute centiloid from PiB SUVr using our pipeline-derived anchors:
# CL = 100 * (PiB - yc_mean) / (ad_mean - yc_mean)
compute_centiloid_for_pib() {
  python3 - <<PY
import sys, csv
yc_mean=${yc_mean}
ad_mean=${ad_mean}
infile="${1}"
outfile="${2}"
with open(infile) as inf, open(outfile,'w',newline='') as outf:
    r=csv.DictReader(inf)
    fieldnames = r.fieldnames + ['PiB_CalcSUVr','Centiloid']
    w=csv.DictWriter(outf, fieldnames=fieldnames)
    w.writeheader()
    for row in r:
        # expect a 'tracer_suvr' column if converting tracer->pib rather than measured PiB
        tracer=float(row.get('tracer_suvr') or 'nan')
        # if there is a 'pib_suvr' column, treat that as measured PiB
        pib_str = row.get('pib_suvr')
        if pib_str and pib_str.strip() != '':
            try:
                pib = float(pib_str)
            except:
                pib = float('nan')
        else:
            # in this mode, caller should have replaced 'PiB_CalcSUVr' prior; handle nan
            pib = float('nan')
        # compute centiloid if we have pib and valid anchors
        if not (pib!=pib):  # not nan
            CL = 100.0 * (pib - yc_mean) / (ad_mean - yc_mean) if (ad_mean - yc_mean) != 0 else float('nan')
            row['PiB_CalcSUVr']=f"{pib:.6f}"
            row['Centiloid']=f"{CL:.6f}"
        else:
            row['PiB_CalcSUVr']='NA'
            row['Centiloid']='NA'
        w.writerow(row)
PY
}

# Helper: fit regression if paired CSV is present
if [[ -n "$PAIRED_CSV" && -f "$PAIRED_CSV" ]]; then
  echo "Fitting tracer->PiB regression from paired CSV: $PAIRED_CSV"
  # Normalize CSV header & compute regression with Python (outputs slope/intercept/R2)
  python3 - <<PY > "$REG_DIR/regression_summary.txt"
import pandas as pd, sys, numpy as np
fn="$PAIRED_CSV"
df=pd.read_csv(fn)
# accept headers with or without names; try to find columns
cols = df.columns.str.lower()
# find best-match columns
try:
    tracer_col = df.columns[[c.lower() for c in df.columns].index('tracer_suvr')]
    pib_col = df.columns[[c.lower() for c in df.columns].index('pib_suvr')]
except Exception:
    # fallback: try heuristics
    cand_tracer = [c for c in df.columns if 'tracer' in c.lower() or 'fbb' in c.lower() or 'fbp' in c.lower() or 'flor' in c.lower()]
    cand_pib = [c for c in df.columns if 'pib' in c.lower()]
    if cand_tracer and cand_pib:
        tracer_col=cand_tracer[0]; pib_col=cand_pib[0]
    else:
        print('ERROR: could not autodetect tracer_suvr and pib_suvr columns in', fn, file=sys.stderr)
        sys.exit(2)
# drop rows with NaNs in either
pair = df[[tracer_col, pib_col]].dropna().astype(float)
x = pair[tracer_col].values
y = pair[pib_col].values
A = np.vstack([x, np.ones(len(x))]).T
m, c = np.linalg.lstsq(A, y, rcond=None)[0]
# compute R^2
y_pred = m * x + c
ss_res = ((y - y_pred)**2).sum()
ss_tot = ((y - y.mean())**2).sum()
r2 = 1 - ss_res/ss_tot if ss_tot!=0 else float('nan')
out = {
    'n_pairs': len(x),
    'slope': float(m),
    'intercept': float(c),
    'R2': float(r2)
}
print("Regression fit results (PiB = intercept + slope * tracer):")
print(out)
# write a small CSV mapping for easy application
pd.DataFrame([out]).to_csv("$REG_DIR/regression_parameters.csv", index=False)
# also write the paired data used
pair.to_csv("$REG_DIR/paired_used_for_fit.csv", index=False)
PY

  if [[ ! -f "$REG_DIR/regression_parameters.csv" ]]; then
    echo "Regression failed. See $REG_DIR/regression_summary.txt for details."
    # still continue but no conversion
  else
    echo "Regression parameters saved: $REG_DIR/regression_parameters.csv"
    # load slope/intercept in bash
    slope=$(awk -F, 'NR==2{print $3}' "$REG_DIR/regression_parameters.csv")
    intercept=$(awk -F, 'NR==2{print $2}' "$REG_DIR/regression_parameters.csv")
    r2=$(awk -F, 'NR==2{print $4}' "$REG_DIR/regression_parameters.csv")
    echo "Using intercept=$intercept slope=$slope R2=$r2"

    # If user provided to_convert CSV, apply regression to compute PiB_CalcSUVr then Centiloid
    if [[ -n "$TO_CONVERT_CSV" && -f "$TO_CONVERT_CSV" ]]; then
      echo "Converting tracer SUVRs from $TO_CONVERT_CSV -> PiB_CalcSUVr -> Centiloid"
      python3 - <<PY
import pandas as pd, numpy as np, sys
infn="$TO_CONVERT_CSV"
outf="$CONVERT_OUT"
df=pd.read_csv(infn)
if 'tracer_suvr' not in df.columns:
    # try case-insensitive
    mapping={c:c for c in df.columns}
    for c in df.columns:
        if c.lower()=='tracer_suvr': mapping['tracer_suvr']=c
df=df.rename(columns={c:c for c in df.columns})
# load regression
reg = pd.read_csv("$REG_DIR/regression_parameters.csv")
slope = float(reg.loc[0,'slope'])
intercept = float(reg.loc[0,'intercept'])
yc_mean = float(${yc_mean:-'nan'})
ad_mean = float(${ad_mean:-'nan'})
def apply_row(x):
    try:
        ts=float(x)
    except:
        return pd.Series([float('nan'),float('nan')])
    pib = intercept + slope * ts
    cl = 100.0 * (pib - yc_mean) / (ad_mean - yc_mean) if (ad_mean - yc_mean)!=0 else float('nan')
    return pd.Series([pib,cl])
if 'tracer_suvr' not in df.columns:
    # try find numeric column
    cand=[c for c in df.columns if 'suv' in c.lower() or 'tracer' in c.lower()]
    if not cand:
        raise SystemExit("Cannot find tracer_suvr column in to_convert CSV")
    tracer_col=cand[0]
else:
    tracer_col='tracer_suvr'
res = df[tracer_col].apply(apply_row)
res.columns=['PiB_CalcSUVr','Centiloid']
outdf = pd.concat([df.reset_index(drop=True), res], axis=1)
outdf.to_csv(outf, index=False)
print("Wrote converted file:", outf)
# write a simple scatter plot of tracer->pib mapping (paired data) and save
try:
    import matplotlib.pyplot as plt
    paired=pd.read_csv("$REG_DIR/paired_used_for_fit.csv")
    x=paired.iloc[:,0].values; y=paired.iloc[:,1].values
    xx = np.linspace(min(x), max(x), 100)
    yy = intercept + slope*xx
    plt.figure(figsize=(4,4))
    plt.scatter(x,y)
    plt.plot(xx,yy,label=f"y={intercept:.3f}+{slope:.3f}x")
    plt.xlabel("Tracer SUVr")
    plt.ylabel("PiB SUVr")
    plt.title("Tracer -> PiB regression (paired data)")
    plt.legend()
    plt.tight_layout()
    plt.savefig("$REG_DIR/regression_plot.png", dpi=150)
except Exception as e:
    print("Plotting failed:", e)
PY
    else
      # No to_convert provided: we can create a file from the paired CSV subjects (for which we have tracer_suvr)
      echo "No --to_convert_csv provided. Creating conversion file from paired data subjects."
      python3 - <<PY
import pandas as pd
pair=pd.read_csv("$REG_DIR/paired_used_for_fit.csv")
reg=pd.read_csv("$REG_DIR/regression_parameters.csv")
slope=float(reg.loc[0,'slope']); intercept=float(reg.loc[0,'intercept'])
yc_mean = float(${yc_mean:-'nan'})
ad_mean = float(${ad_mean:-'nan'})
pair['PiB_CalcSUVr'] = intercept + slope * pair.iloc[:,0]
pair['Centiloid'] = 100.0 * (pair['PiB_CalcSUVr'] - yc_mean) / (ad_mean - yc_mean)
pair.to_csv("$CONVERT_OUT", index=False)
print("Wrote converted file:", "$CONVERT_OUT")
PY
    fi
  fi

else
  echo "No paired CSV provided."
  if [[ -n "$TO_CONVERT_CSV" && -f "$TO_CONVERT_CSV" ]]; then
    # assume to_convert contains measured PiB values? try to detect
    echo "Attempting to convert measured PiB SUVr in $TO_CONVERT_CSV -> Centiloid (no regression)"
    # try to detect a 'pib_suvr' column; otherwise fail
    python3 - <<PY
import pandas as pd,sys
fn="$TO_CONVERT_CSV"
df=pd.read_csv(fn)
if 'pib_suvr' in df.columns:
    yc_mean=float(${yc_mean:-'nan'}); ad_mean=float(${ad_mean:-'nan'})
    def cl_from_pib(pib):
        try:
            return 100.0 * (float(pib) - yc_mean) / (ad_mean - yc_mean)
        except:
            return float('nan')
    df['PiB_CalcSUVr']=df['pib_suvr']
    df['Centiloid']=df['pib_suvr'].apply(cl_from_pib)
    df.to_csv("$CONVERT_OUT", index=False)
    print("Wrote converted file (from measured PiB):", "$CONVERT_OUT")
else:
    print("ERROR: to_convert CSV does not contain a 'pib_suvr' column and no paired regression was provided.", file=sys.stderr)
    sys.exit(2)
PY
  else
    echo "No --to_convert_csv provided. No conversion done."
  fi
fi

echo "Centiloid conversion step finished. See $CONVERT_OUT (if created) and $REG_DIR/regression_parameters.csv (if regression was fitted)."

# final message
echo "Pipeline complete. Outputs:"
echo " - Subject SUVR CSV: $CSV_OUT"
echo " - Group summary: $GROUP_SUM"
echo " - Regression folder: $REG_DIR"
echo " - Converted centiloids (if created): $CONVERT_OUT"
