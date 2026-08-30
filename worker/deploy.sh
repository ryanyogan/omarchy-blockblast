#!/usr/bin/env bash
# One-shot deploy: creates the D1 database if needed, wires its id into
# wrangler.jsonc, applies migrations, deploys the Worker, and points the
# plugin at the resulting URL. Needs `npx wrangler login` first.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
DB=blast-leaderboard

if grep -q REPLACE_WITH_D1_ID wrangler.jsonc; then
  echo "Creating D1 database $DB"
  id=$(npx wrangler d1 create "$DB" 2>/dev/null | grep -oE '"database_id": *"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
  if [ -z "$id" ]; then
    id=$(npx wrangler d1 info "$DB" --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).uuid||JSON.parse(s).id||""))')
  fi
  [ -n "$id" ] || { echo "could not find the database id; paste it into wrangler.jsonc"; exit 1; }
  sed -i "s/REPLACE_WITH_D1_ID/$id/" wrangler.jsonc
  echo "database_id = $id"
fi

npx wrangler d1 migrations apply "$DB" --remote
out=$(npx wrangler deploy 2>&1 | tee /dev/stderr)
url=$(echo "$out" | grep -oE 'https://[a-z0-9.-]+\.workers\.dev' | head -1)
if [ -n "$url" ]; then
  sed -i "s#readonly property string builtinApi: \"[^\"]*\"#readonly property string builtinApi: \"$url\"#" ../Service.qml
  echo
  echo "Deployed: $url"
  echo "Service.qml now points at it. Restart the shell (omarchy-restart-shell) and play."
fi
