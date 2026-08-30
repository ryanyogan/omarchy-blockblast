# Changelog

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
