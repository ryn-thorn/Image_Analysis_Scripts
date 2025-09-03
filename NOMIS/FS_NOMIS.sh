#######################################
# FS_NOMIS pipeline
#######################################
#
#######################################
# To run this script: 
# ./FS_NOMIS.sh --input /base/derivatives/freesurfer --csv /path/to/PUMA_norms.csv --nomis /path/to/NOMIS.py --output /base/derivatives/nomis
#######################################

set -euo pipefail

# --- Functions ---
usage() {
    echo "Usage: $0 --input /path/to/freesurfer_data --csv norms.csv --nomis /path/to/NOMIS.py --output /path/to/nomis_output [--subjects sub-001 sub-002 ...]"
    exit 1
}

error_exit() {
    echo -e "\033[1;31mERROR:\033[0m $1" >&2
    exit 1
}

check_dep() {
    command -v "$1" >/dev/null 2>&1 || error_exit "Required dependency '$1' not found in PATH."
}

# --- Defaults ---
BASE=""
CSV=""
OUTROOT=""
NOMIS_SCRIPT=""
SUBJECTS=()

# --- Parse arguments ---
INPUT=""
CSV=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input) INPUT="$2"; shift 2;;
        --csv) CSV="$2"; shift 2;;
        --nomis) NOMIS_SCRIPT="$2"; shift 2;;
        --subjects) shift; while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do SUBJECTS+=("$1"); shift; done;;
        --output) OUTROOT="$2"; shift 2;;
        -h|--help) usage;;
        *) echo "Unknown argument: $1"; usage;;
    esac
done

[[ -z "$INPUT" ]] && usage
[[ -z "$CSV" ]] && usage
[[ -z "$NOMIS_SCRIPT" ]] && usage
[[ -z "$OUTROOT" ]] && usage
[[ ! -d "$INPUT" ]] && error_exit "Input directory '$INPUT' not found."
[[ ! -f "$CSV" ]] && error_exit "CSV file '$CSV' not found."
[[ ! -f "$NOMIS_SCRIPT" ]] && error_exit "NOMIS script '$NOMIS_SCRIPT' not found."
mkdir -p "$OUTROOT"

# --- Logging ---
LOGFILE="$OUTROOT/FS_NOMIS.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "#######################################" >> "$LOGFILE"
echo "Run started: $(date)" >> "$LOGFILE"
echo "Input: $INPUT" >> "$LOGFILE"
echo "CSV: $CSV" >> "$LOGFILE"
echo "Output: $OUTROOT" >> "$LOGFILE"
echo "NOMIS script: $NOMIS_SCRIPT" >> "$LOGFILE"
echo "Subjects: ${SUBJECTS[*]:-ALL}" >> "$LOGFILE"
echo "#######################################" >> "$LOGFILE"

# --- Dependency checks ---
check_dep recon-all
check_dep conda
check_dep python

# --- Subject list ---
if [[ ${#SUBJECTS[@]} -eq 0 ]]; then
    SUBJECTS=($(ls "$INPUT"))
fi

# --- Process subjects ---
for subj in "${SUBJECTS[@]}"; do
    echo -e "\033[1;36mProcessing subject: $subj\033[0m"

    subj_dir="$INPUT/$subj"
    t1="$subj_dir/${subj}_T1.nii"

    [[ ! -d "$subj_dir" ]] && error_exit "Subject directory $subj_dir missing."
    [[ ! -f "$t1" ]] && error_exit "Missing T1 file: $t1"

    recon-all -all -i "$t1" -sd "$subj_dir" -subjid "$subj"

    cp -r "$subj_dir/$subj" "$OUTROOT/"
    rm -rf "$subj_dir/fslaverage"
done

# --- Run NOMIS ---
echo "Running NOMIS..."
conda activate nomis || error_exit "Could not activate conda env 'nomis'"
python "$NOMIS_SCRIPT" -csv "$CSV" -s "$OUTROOT" -o "$OUTROOT"

echo -e "\033[1;32mFS_NOMIS pipeline completed!\033[0m"
echo "Run completed: $(date)" >> "$LOGFILE"