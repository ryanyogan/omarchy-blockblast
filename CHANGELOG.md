# Changelog

## 1.2.5

Third hardening pass from marketplace review, no gameplay changes:

- `Blast.desktop` runs one fixed-path command, `/usr/bin/omarchy-shell`, with no shell in between. Dismissing the shell's "Launching…" feedback moved into the overlay, which now gets a `launcher` flag from the app menu entry
- `install.sh` no longer calls `update-desktop-database` or `gtk-update-icon-cache`: the app menu watches the directory itself, so the installer touches exactly the two files it publishes and nothing else, and runs no command found through `PATH`
- `test/io.test.py` checks the desktop entry's `Exec` line stays absolute and shell-free

## 1.2.4

Second hardening pass from marketplace review, no gameplay changes:

- `install.sh` no longer copies by pathname. The desktop entry and icon are published by `blast-io.py`, which walks every directory under `$HOME` without following symlinks, checks each one is yours, creates missing ones itself, refuses to replace anything at the destination that is not a plain file you own, and writes each file to a temp name, fsyncs it, and renames it into place. A crash mid-install leaves either the old file or the new one
- A failed save is no longer treated as a success. The service checks the helper's exit status, keeps the newer state in memory, retries on its own a bounded number of times (1s, 3s, 9s, 27s), and then leaves it to the next change, the next open, or `:save`. The overlay shows the reason and an `unsaved` marker in the footer until the write lands, and opening the game never reloads the disk over unsaved changes, so `:leaderboard off` and `:forget` cannot quietly revert
- A save file the helper refuses to read (wrong owner, not a regular file, too large) is reported and the game plays from defaults without ever writing over it
- `:save` command, and `test/io.test.py` covers the helper's install, write, and refusal paths

## 1.2.3

Security hardening pass from marketplace review, no gameplay changes:

- All state-file and network I/O moved into `blast-io.py`, a single-process helper. State reads and writes walk `~/.local/state/blast` component by component with `O_NOFOLLOW`, verify ownership on the opened descriptors, force the directory to 0700, and replace the file atomically relative to the held directory fd with file and directory fsync
- The leaderboard client refuses redirects, caps every response at 256 KB before parsing, and only talks to `https://` endpoints: `:api` and `BLAST_API` values that are not https (or http to localhost for development) are rejected and never receive the token
- Every API response is rebuilt field by field to a fixed schema and cardinality before it is rendered or persisted; tags, tokens, errors and leaderboard entries all have hard length and range caps, and an oversized token or state object is never written to disk
- Every dynamic `Text` sink renders as `Text.PlainText`
- Every helper process runs under a deadline and is killed and cleaned up in full if it overruns; network requests are queued one at a time with a bounded queue

## 1.2.2

- The dropdown wears the same header as the other plugins: block mark, name, a small-caps status line with your best and world rank, a refresh action, and tighter margins
- Pills are gone. Period selectors are flat text tabs with an accent rule under the active one, in the dropdown and the game, and the game tabs are clickable now
- Blocks went holographic: a translucent pane of their own colour behind a luminous edge, flat as projected glass, replacing the candy gloss everywhere: board, tray, logos, mini board, medals. The placement ghost already spoke this language
- Waiting on the leaderboard shows ghost rows in the shape the real ones will take, breathing gently, instead of a "Fetching" line
- The play button is a flat accent bar flush with the card: edge to edge, in line with the border, taking the card's own bottom corners

## 1.2.1

- The dropdown got a real design: a live miniature of your saved board with its score, block-styled podium medals and Play button, proportional type, and the world's top eight making better use of the space
- The leaderboard server moved to its own repo, [blockblast-server](https://github.com/ryanyogan/blockblast-server), so the plugin repo is now purely the game, which also slims what `omarchy plugin add` clones

## 1.2.0

- Bar widget: a theme-colored block cluster; left click drops down the leaderboard with a Start/Resume button, right click launches the game, `showBest` puts your best score in the bar
- New screenshots and gameplay capture in Solitude and Retro-82

## 1.1.1

- Leaderboard served from https://blockblast.yogan.dev
- Launching from the app menu no longer leaves the shell's "Launching…" popup hanging

## 1.1.0

- Leaderboard redesigned: proportional type, medals, zebra rows, period pills
- One gliding ghost piece instead of per-cell ghosts; settle glow on landings; the selected tray piece bobs
- First-launch intro card; help explains the vim-motion goal and exactly what the server keeps
- `:leaderboard off` turns off all networking; `:opacity 20-100` sets the background dimming
- Ambient motion now sleeps five seconds after the last keypress: an open, untouched board costs ~0.4% of a core instead of ~6-9%

## 1.0.0

First release. 🧱

- 8x8 board, three-piece tray, 41 shapes with weighted draws
- Vim movement: hjkl, 0 $, gg G, 1 2 3, w b, enter
- Landing pops, sweeping line clears with shards, floating points, combo and board-clear banners
- Block colors from the active theme's colors.toml, light and dark
- Saves the run in progress and resumes it
- Local best and recent runs
- Gamer tags and a global leaderboard (all time, week, today) on Cloudflare Workers + D1
- `:` command line
- Launches from the app menu, no bar widget
