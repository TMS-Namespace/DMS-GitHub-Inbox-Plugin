#!/bin/sh
# setup-symlink.sh - Link this plugin into the DMS plugins directory

PLUGIN_DIR="$HOME/.config/DankMaterialShell/plugins"
PLUGIN_NAME="GitHubInboxPlugin"
SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$PLUGIN_DIR"
ln -sfn "$SOURCE_DIR" "$PLUGIN_DIR/$PLUGIN_NAME"

echo "Symlinked: $PLUGIN_DIR/$PLUGIN_NAME -> $SOURCE_DIR"
echo ""
echo "Next steps:"
echo "  1. Open DMS Settings -> Plugins"
echo "  2. Click 'Scan for Plugins'"
echo "  3. Toggle 'GitHub Inbox' on"
echo "  4. Add widget to DankBar"
echo "  5. Restart DMS or run: dms ipc call plugins reload github-inbox"
