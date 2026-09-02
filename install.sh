#!/usr/bin/env bash
# Puts Blast in the app menu. Run once after `omarchy plugin add`. Safe to rerun.
#
# The two files (desktop entry, icon) are published by blast-io.py, the same
# helper the game uses for its save file: every directory under $HOME is
# opened without following symlinks and checked to be yours, anything at the
# destination that is not a plain file you own is refused, and each file is
# written to a temp name, fsynced, and renamed into place. Nothing else is
# touched. Removal is two rm lines, see the README.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
/usr/bin/python3 "$here/blast-io.py" install
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
echo "Blast is in your app menu. Or bind it: omarchy-shell shell toggle ryanyogan.blast '{}'"
