#!/usr/bin/env bash
# Copies the latest Xcode-built PDFUnlock.app into ./debug/ so it has a
# stable path you can launch without spelunking through DerivedData.
#
# Usage:
#   ./copy_to_debug.sh           # refresh after Xcode build
#   ./copy_to_debug.sh --launch  # refresh + open the app

set -euo pipefail

# Resolve project root regardless of cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEBUG_DIR="$PROJECT_ROOT/debug"
DERIVED_APP="$HOME/Library/Developer/Xcode/DerivedData/PDFUnlock-bazwuvhkbkcdxrhdnilfbcudxstm/Build/Products/Debug/PDFUnlock.app"

if [ ! -d "$DERIVED_APP" ]; then
    echo "error: built .app not found at:"
    echo "  $DERIVED_APP"
    echo "build the project first (open PDFUnlock.xcodeproj, ⌘B), then re-run."
    exit 1
fi

mkdir -p "$DEBUG_DIR"
# Remove whatever's there (file, symlink, or directory) and replace.
rm -rf "$DEBUG_DIR/PDFUnlock.app"
cp -R "$DERIVED_APP" "$DEBUG_DIR/PDFUnlock.app"
echo "✓ Copied → $DEBUG_DIR/PDFUnlock.app"

if [ "${1:-}" = "--launch" ]; then
    open "$DEBUG_DIR/PDFUnlock.app"
    echo "✓ Launched"
fi