#######################################
# FS_NOMIS pipeline
#######################################
#
#######################################
# To run this script: 
# ./FS_NOMIS.sh --base /base/derivatives/freesurfer --csv /path/to/PUMA_norms.csv --nomis /path/to/NOMIS.py --output /base/derivatives/nomis --env [name of nomis conda env]
#######################################

set -euo pipefail

# --- Functions ---
usage() {
    echo "Usage: $0 --base /path/to/freesurfer_subjects --csv norms.csv --output /path/to/output --nomis /path/to/NOMIS.py [--env conda_env]"
    exit 1
}

error_exit() {
    echo -e "\033[1;31mERROR:\033[0m $1" >&2
    exit 1
}

check_dep() {
    command -v "$1" >/dev/null 2>&1 || error_exit "Required dependency '$1' not found in PATH."
}

# --- Required arguments ---
BASE=""
CSV=""
OUTROOT=""
NOMIS_SCRIPT=""
CONDA_ENV="nomis"   # default

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base) BASE="$2"; shift 2;;
        --csv) CSV="$2"; shift 2;;
        --output) OUTROOT="$2"; shift 2;;
        --nomis) NOMIS_SCRIPT="$2"; shift 2;;
        --env) CONDA_ENV="$2"; shift 2;;
        -h|--help) usage;;
        *) echo "Unknown argument: $1"; usage;;
    esac
done

# --- Validate required args ---
[[ -z "$BASE" ]] && usage
[[ -z "$CSV" ]] && usage
[[ -z "$OUTROOT" ]] && usage
[[ -z "$NOMIS_SCRIPT" ]] && usage

[[ ! -d "$BASE" ]] && error_exit "Base directory '$BASE' not found."
[[ ! -f "$CSV" ]] && error_exit "CSV file '$CSV' not found."
[[ ! -f "$NOMIS_SCRIPT" ]] && error_exit "NOMIS script '$NOMIS_SCRIPT' not found."
mkdir -p "$OUTROOT"

# --- Logging ---
LOGFILE="$OUTROOT/FS_NOMIS.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "#######################################" >> "$LOGFILE"
echo "Run started: $(date)" >> "$LOGFILE"
echo "Base (Freesurfer SUBJECTS_DIR): $BASE" >> "$LOGFILE"
echo "CSV: $CSV" >> "$LOGFILE"
echo "Output: $OUTROOT" >> "$LOGFILE"
echo "NOMIS script: $NOMIS_SCRIPT" >> "$LOGFILE"
echo "Conda env: $CONDA_ENV" >> "$LOGFILE"
echo "#######################################" >> "$LOGFILE"

# --- Initialize conda (for non-interactive shells) ---
if [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
elif [[ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]]; then
    source "$HOME/anaconda3/etc/profile.d/conda.sh"
elif [[ -f "/opt/miniconda3/etc/profile.d/conda.sh" ]]; then
    source "/opt/miniconda3/etc/profile.d/conda.sh"
elif [[ -f "/opt/anaconda3/etc/profile.d/conda.sh" ]]; then
    source "/opt/anaconda3/etc/profile.d/conda.sh"
else
    echo "ERROR: Could not find conda.sh. Please update FS_NOMIS.sh with your Conda install path." >&2
    exit 1
fi

# --- Dependency checks ---
check_dep conda
check_dep python

# --- Run NOMIS ---
echo "Running NOMIS in conda env: $CONDA_ENV ..."
conda activate "$CONDA_ENV" || error_exit "Could not activate conda env '$CONDA_ENV'"
python "$NOMIS_SCRIPT" -csv "$CSV" -s "$BASE" -o "$OUTROOT"

echo -e "\033[1;32mFS_NOMIS pipeline completed!\033[0m"
echo "Run completed: $(date)" >> "$LOGFILE"