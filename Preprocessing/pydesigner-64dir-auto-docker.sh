#!/usr/bin/env bash
#######################################
#
# PyDesigner Preprocessing with Docker
# See https://pydesigner.readthedocs.io/en/latest/index.html for more details
#
#######################################
#
# Usage: /path/to/pyd_preproc.sh --base /path/to/BIDS_folder 
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
    echo "Usage: $0 --base <path_to_BIDS_folder>"
    exit 1
fi

if [[ ! -d "$BASE" ]]; then
    echo "ERROR: Base directory $BASE does not exist."
    exit 1
fi

# Docker image + mount point
PYD_DOCKER_IMG="dmri/neurodock"
PYD_MOUNT="/data"


#####################################
# Setup output + logging (UNCHANGED)
#####################################
OUT="$BASE/derivatives/Preprocessing/pydesigner/dki-pydesigner"
mkdir -p "$OUT"
ERRORLOG="$OUT/error.log"
touch "$ERRORLOG"

#####################################
# Main loop (BIDS sub/session)
#####################################
for ses_path in "$BASE"/sub-*/ses-*; do
    [[ -d "$ses_path" ]] || continue

    subj=$(basename "$(dirname "$ses_path")")
    ses=$(basename "$ses_path")

    subj_out="$OUT/$subj/$ses"

    # Skip if already processed
    if [[ -d "$subj_out"/metrics/dti_fa* ]]; then
        echo -e "\033[1;33mSkipping $subj $ses (already processed).\033[0m"
        continue
    fi

    echo -e "\033[1;36mProcessing $subj $ses\033[0m"
    mkdir -p "$subj_out"

    dwi_dir="$ses_path/dwi"
    if [[ ! -d "$dwi_dir" ]]; then
        error_exit "Missing dwi directory for $subj $ses"
        continue
    fi

    # Find files
    shopt -s nullglob nocaseglob
    dki_main=("$dwi_dir"/*DKI_64dir.nii.gz)
    dki_topup=("$dwi_dir"/*DKI_64dir_TOPUP.nii.gz)
    shopt -u nullglob nocaseglob

    if [[ ${#dki_main[@]} -eq 0 ]]; then
        error_exit "No DKI nifti found for $subj $ses"
        continue
    fi

    input1="${dki_main[0]}"
    input2="${dki_topup[0]:-}"

    # Copy main DKI (keep original name)
    safe1="$subj_out/$(basename "$input1")"
    cp "$input1" "$safe1"

    # Copy accompanying bvec/bval if they exist
    for ext in bvec bval; do
        if [[ -f "${input1%.nii.gz}.$ext" ]]; then
            cp "${input1%.nii.gz}.$ext" "$subj_out/"
        fi
    done

    # Copy JSON if present
    if [[ -f "${input1%.nii.gz}.json" ]]; then
        cp "${input1%.nii.gz}.json" "$subj_out/"
    fi


    # Copy TOPUP if present (keep original name)
    if [[ -n "$input2" ]]; then
        safe2="$subj_out/$(basename "$input2")"
        cp "$input2" "$safe2"

        if [[ -f "${input2%.nii.gz}.json" ]]; then
            cp "${input2%.nii.gz}.json" "$subj_out/"
        fi
    fi


	echo "  -> Running PyDesigner (Docker)..."
	
	# Convert host paths to container paths
	safe1_docker="$PYD_MOUNT${safe1#$BASE}"
	subj_out_docker="$PYD_MOUNT${subj_out#$BASE}"
	
	if [[ -n "${safe2:-}" ]]; then
		safe2_docker="$PYD_MOUNT${safe2#$BASE}"
	
		docker run --rm \
			-v "$BASE:$PYD_MOUNT" \
			"$PYD_DOCKER_IMG" \
			pydesigner -o "$subj_out_docker" -s "$safe1_docker" "$safe2_docker" \
			|| error_exit "PyDesigner failed for $subj $ses"
	else
		docker run --rm \
			-v "$BASE:$PYD_MOUNT" \
			"$PYD_DOCKER_IMG" \
			pydesigner -o "$subj_out_docker" -s "$safe1_docker" \
			|| error_exit "PyDesigner failed for $subj $ses"
	fi

    echo -e "\033[1;32mFinished $subj $ses.\033[0m"
done

echo -e "\033[1;32mAll subjects/sessions processed (see $ERRORLOG for any errors).\033[0m"

