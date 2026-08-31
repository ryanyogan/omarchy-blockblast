# Changelog

## 1.2.1

- The dropdown got a real design: a live miniature of your saved board with its score, block-styled podium medals and Play button, proportional type, and the world's top eight making better use of the space
- The leaderboard server moved to its own repo, [blockblast-server](https://github.com/ryanyogan/blockblast-server) — the plugin repo is now purely the game, which also slims what `omarchy plugin add` clones

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
