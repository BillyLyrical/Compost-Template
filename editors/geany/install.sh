#!/bin/bash
# Install Compost syntax highlighting for Geany

GEANY_CONFIG="$HOME/.config/geany"
FILETYPES_DIR="$GEANY_CONFIG/filedefs"

# Create directory if it doesn't exist
mkdir -p "$FILETYPES_DIR"

# Copy the filetype definition
cp "$(dirname "$0")/filetypes.compost" "$FILETYPES_DIR/"

echo "Installed Compost syntax highlighting for Geany"
echo "Restart Geany to use it"
