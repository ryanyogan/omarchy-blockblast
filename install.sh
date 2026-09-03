#!/bin/bash
# Puts Blast in the app menu. Run once after `omarchy plugin add`. Safe to rerun.
#
# The two files (desktop entry, icon) are published by blast-io.py, the same
# helper the game uses for its save file: every directory under $HOME is
# opened without following symlinks and checked to be yours, anything at the
# destination that is not a plain file you own is refused, and each file is
# written to a temp name, fsynced, and renamed into place. Nothing else is
# touched: the app menu watches that directory itself, so no cache refresh
# is run. Removal is two rm lines, see the README.
set -euo pipefail
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
/usr/bin/python3 "$here/blast-io.py" install
echo "Blast is in your app menu. Or bind it: omarchy-shell shell toggle ryanyogan.blast '{}'"
