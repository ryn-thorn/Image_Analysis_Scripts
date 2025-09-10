#!/usr/bin/env bash
#######################################
#
# PyDesigner Preprocessing hands off
# w/ error handling and logging
# Original: 9/21/21 | Updated: 2025
# See https://pydesigner.readthedocs.io/en/latest/index.html for more details
#
#######################################
#
# Expected folder structure:
# BIDS_folder
#   derivatives
#   Subj1/
#   Subj2/
#   SubjN/
#
#######################################
#
# To call this script: /path/to/pyd_preproc.sh --base /path/to/BIDS_folder
#
#######################################

set -euo pipefail

#####################################
# Functions
#####################################

error_exit() {
    local msg="$1"
    echo -e "\033[1;31mERROR: $msg\033[0m"
    echo "$(date +"%Y-%m-%d %H:%M:%S") [ERROR] $msg" >> "$ERRORLOG"
}

#####################################
# Arguments
#####################################
BASE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base)
            BASE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$BASE" ]]; then
    echo "Usage: $0 --base <path_to_main_study_folder>"
    exit 1
fi

if [[ ! -d "$BASE" ]]; then
    echo "ERROR: Base directory $BASE does not exist."
    exit 1
fi

#####################################
# Setup output + logging
#####################################
OUTROOT="$BASE/derivatives/pydesigner"
mkdir -p "$OUTROOT"
ERRORLOG="$OUTROOT/error.log"
touch "$ERRORLOG"

#####################################
# Main loop
#####################################
for subj_path in "$BASE"/sub-*; do
    [[ -d "$subj_path" ]] || continue
    subj=$(basename "$subj_path")

    # Skip derivatives if it matches sub- pattern
    if [[ "$subj" == "derivatives" ]]; then
        continue
    fi

    subj_out="$OUTROOT/$subj"

    # Skip if already processed
    if [[ -d "$subj_out" ]]; then
        echo -e "\033[1;33mSkipping $subj (already processed).\033[0m"
        continue
    fi

    echo -e "\033[1;36mProcessing subject: $subj\033[0m"
    mkdir -p "$subj_out"
    echo "Output directory for $subj: $subj_out"

    dmri_dir="$subj_path/dmri"
    if [[ ! -d "$dmri_dir" ]]; then
        error_exit "Missing dmri directory for $subj"
        continue
    fi

    # Find files
    shopt -s nullglob nocaseglob
    dki_main=("$dmri_dir"/DKI*.nii)
    dki_topup=("$dmri_dir"/DKI*TOPUP*.nii "$dmri_dir"/DKI*TOP_UP*.nii)
    shopt -u nullglob nocaseglob

    if [[ ${#dki_main[@]} -eq 0 ]]; then
        error_exit "No DKI nifti found for $subj"
        continue
    fi

    # Take the first matches
    input1="${dki_main[0]}"
    input2="${dki_topup[0]:-}"

    # Sanitize filenames (replace dots with underscores, keep extension)
	safe1_base="$(basename "$input1" .nii | tr '.' '_')"
	safe1="$subj_out/${safe1_base}.nii"
	cp "$input1" "$safe1"
	
	# Copy matching JSON if it exists
	if [[ -f "${input1%.nii}.json" ]]; then
		cp "${input1%.nii}.json" "$subj_out/${safe1_base}.json"
	fi
	
	if [[ -n "$input2" ]]; then
		safe2_base="$(basename "$input2" .nii | tr '.' '_')"
		safe2="$subj_out/${safe2_base}.nii"
		cp "$input2" "$safe2"
	
		if [[ -f "${input2%.nii}.json" ]]; then
			cp "${input2%.nii}.json" "$subj_out/${safe2_base}.json"
		fi
	fi

    echo "  -> Running PyDesigner..."
    if [[ -n "${safe2:-}" ]]; then
        pydesigner -o "$subj_out" -s "$safe1" "$safe2" || error_exit "PyDesigner failed for $subj"
    else
        pydesigner -o "$subj_out" -s "$safe1" || error_exit "PyDesigner failed for $subj"
    fi

    echo -e "\033[1;32mFinished $subj.\033[0m"
done

echo -e "\033[1;32mAll subjects processed (see $ERRORLOG for any errors).\033[0m"
