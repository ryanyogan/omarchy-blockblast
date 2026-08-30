#!/usr/bin/env bash
# Puts Blast in the app menu. Run once after `omarchy plugin add`. Safe to rerun.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
apps="$HOME/.local/share/applications"
icons="$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$apps" "$icons"
cp "$here/Blast.desktop" "$apps/Blast.desktop"
cp "$here/assets/icon.svg" "$icons/blast.svg"
command -v update-desktop-database >/dev/null && update-desktop-database "$apps" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
echo "Blast is in your app menu. Or bind it: omarchy-shell shell toggle ryanyogan.blast '{}'"
