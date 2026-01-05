#!/bin/sh

# POSIX-safe, portable FreeSurfer BIDS runner

BIDS_ROOT="$1"
FS_VERSION="6.0"
IMAGE="freesurfer:6.0"

if [ -z "$BIDS_ROOT" ]; then
    echo "Usage: run_freesurfer_bids /path/to/BIDS_root"
    exit 1
fi

if [ ! -d "$BIDS_ROOT" ]; then
    echo "Error: BIDS root not found: $BIDS_ROOT"
    exit 1
fi

# Check that Docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed or not in PATH"
    exit 1
fi

# Check that Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker is installed but not running"
    echo "Please start Docker Desktop (macOS/Windows) or the Docker service (Linux)"
    exit 1
fi


DERIV_ROOT="$BIDS_ROOT/derivatives/Preprocessing/freesurfer/freesurfer_$FS_VERSION"

echo "BIDS root: $BIDS_ROOT"
echo "Output root: $DERIV_ROOT"
echo

for SUB_DIR in "$BIDS_ROOT"/sub-*; do
    [ -d "$SUB_DIR" ] || continue
    SUBJECT=`basename "$SUB_DIR"`

    echo "Subject: $SUBJECT"

    for SES_DIR in "$SUB_DIR"/ses-*; do
        [ -d "$SES_DIR" ] || continue
        SES=`basename "$SES_DIR"`

        ANAT_DIR="$SES_DIR/anat"
        T1="$ANAT_DIR/${SUBJECT}_${SES}_T1w.nii.gz"

        if [ ! -f "$T1" ]; then
            echo "  Missing T1 for $SES, skipping"
            continue
        fi

        OUTDIR="$DERIV_ROOT/$SUBJECT/$SES"

        if [ -d "$OUTDIR/surf" ]; then
            echo "  Already processed $SES, skipping"
            continue
        fi

        mkdir -p "$OUTDIR"

        echo "  Running FreeSurfer for $SES"

        docker run --rm \
            -v "$ANAT_DIR:/data:ro" \
            -v "$OUTDIR:/subjects" \
            "$IMAGE" \
            recon-all \
                -i "/data/`basename "$T1"`" \
                -s "${SUBJECT}_${SES}" \
                -all

        echo "  Finished $SES"
        echo
    done
done

echo "All subjects complete"
