#!/bin/sh

# Installer for freesurfer-6.0-docker tools

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing FreeSurfer Docker tools from:"
echo "  $SCRIPT_DIR"
echo

# Detect shell
SHELL_NAME="$(basename "$SHELL")"

case "$SHELL_NAME" in
    bash)
        RC_FILE="$HOME/.bashrc"
        ;;
    zsh)
        RC_FILE="$HOME/.zshrc"
        ;;
    *)
        RC_FILE="$HOME/.profile"
        ;;
esac

echo "Using shell config file:"
echo "  $RC_FILE"
echo

# Ensure rc file exists
if [ ! -f "$RC_FILE" ]; then
    touch "$RC_FILE"
fi

# Check if already in PATH
case ":$PATH:" in
    *":$SCRIPT_DIR:"*)
        echo "Path already contains this directory. Nothing to do."
        exit 0
        ;;
esac

# Add to PATH
echo "" >> "$RC_FILE"
echo "# FreeSurfer 6.0 Docker tools" >> "$RC_FILE"
echo "export PATH=\"$SCRIPT_DIR:\$PATH\"" >> "$RC_FILE"

echo "✔ Added to PATH"

echo
echo "IMPORTANT:"
echo "Restart your terminal or run:"
echo "  source $RC_FILE"
echo
echo "Then you can run:"
echo "  run_freesurfer_bids /path/to/BIDS"
echo "  run_freesurfer_gui.py"
