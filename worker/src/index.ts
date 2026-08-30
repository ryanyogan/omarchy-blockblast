// Blast leaderboard. One Worker, one D1 database, no accounts beyond a gamer
// tag and the random token that proves it is yours. No logging, no tracking,
// nothing stored about a person except the tag they picked and their scores.
//
//   GET  /                         scoreboard page
//   GET  /v1/health
//   POST /v1/players               { tag }            -> { id, tag, token }
//   POST /v1/players/verify        { token }          -> { tag, best, games, rank }
//   DELETE /v1/players             { token }          -> { ok }
//   GET  /v1/players/:tag                             -> { tag, best, games, rank, recent }
//   POST /v1/scores                { token, score, lines, maxCombo, moves, durationS }
//   GET  /v1/leaderboard?period=all|week|day&limit=25

export interface Env { DB: D1Database }

const TAG_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{1,15}$/
const MAX_SCORE = 5_000_000
const PERIODS: Record<string, number> = { all: 0, week: 7 * 86400, day: 86400 }

type Json = Record<string, unknown>

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, DELETE, OPTIONS",
  "access-control-allow-headers": "content-type",
}

function json(body: Json, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...CORS },
  })
}

function fail(status: number, error: string, extra: Json = {}): Response {
  return json({ ok: false, error, ...extra }, status)
}

async function readJson(req: Request): Promise<Json | null> {
  try {
    const body = await req.json()
    return body && typeof body === "object" ? (body as Json) : null
  } catch {
    return null
  }
}

function now(): number { return Math.floor(Date.now() / 1000) }

function int(v: unknown, min: number, max: number): number | null {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN
  if (!Number.isFinite(n)) return null
  const r = Math.round(n)
  return r < min || r > max ? null : r
}

function randomToken(): string {
  const bytes = new Uint8Array(24)
  crypto.getRandomValues(bytes)
  let s = ""
  for (const b of bytes) s += String.fromCharCode(b)
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("")
}

interface Player { id: string; tag: string; best: number; games: number; created_at: number }

async function playerByToken(env: Env, token: unknown): Promise<Player | null> {
  if (typeof token !== "string" || token.length < 16 || token.length > 128) return null
  const hash = await sha256(token)
  return env.DB.prepare("SELECT id, tag, best, games, created_at FROM players WHERE token_hash = ?")
    .bind(hash).first<Player>()
}

// A player's all-time rank: one plus the number of players with a higher best.
async function rankOf(env: Env, best: number): Promise<number> {
  const above = await env.DB.prepare("SELECT COUNT(*) AS n FROM players WHERE best > ? AND games > 0")
    .bind(best).first<{ n: number }>()
  return (above?.n ?? 0) + 1
}

// ----------------------------------------------------------------- routes

async function registerPlayer(req: Request, env: Env): Promise<Response> {
  const body = await readJson(req)
  const tag = typeof body?.tag === "string" ? body.tag.trim() : ""
  if (!TAG_RE.test(tag)) return fail(400, "Tag must be 2 to 16 letters, numbers, _ or -, and start with a letter or number")

  const token = randomToken()
  const id = crypto.randomUUID()
  const ts = now()
  try {
    await env.DB.prepare(
      "INSERT INTO players (id, tag, tag_key, token_hash, best, games, created_at, last_seen) VALUES (?, ?, ?, ?, 0, 0, ?, ?)",
    ).bind(id, tag, tag.toLowerCase(), await sha256(token), ts, ts).run()
  } catch (e) {
    if (String((e as Error).message).includes("UNIQUE")) return fail(409, "That tag is taken")
    throw e
  }
  return json({ ok: true, id, tag, token }, 201)
}

async function verifyPlayer(req: Request, env: Env): Promise<Response> {
  const body = await readJson(req)
  const player = await playerByToken(env, body?.token)
  if (!player) return fail(401, "Unknown token")
  await env.DB.prepare("UPDATE players SET last_seen = ? WHERE id = ?").bind(now(), player.id).run()
  return json({ ok: true, tag: player.tag, best: player.best, games: player.games, rank: await rankOf(env, player.best) })
}

async function deletePlayer(req: Request, env: Env): Promise<Response> {
  const body = await readJson(req)
  const player = await playerByToken(env, body?.token)
  if (!player) return fail(401, "Unknown token")
  await env.DB.batch([
    env.DB.prepare("DELETE FROM scores WHERE player_id = ?").bind(player.id),
    env.DB.prepare("DELETE FROM players WHERE id = ?").bind(player.id),
  ])
  return json({ ok: true })
}

async function getPlayer(tag: string, env: Env): Promise<Response> {
  if (!TAG_RE.test(tag)) return fail(400, "Bad tag")
  const player = await env.DB.prepare("SELECT id, tag, best, games, created_at FROM players WHERE tag_key = ?")
    .bind(tag.toLowerCase()).first<Player>()
  if (!player) return fail(404, "No such player")
  const recent = await env.DB.prepare(
    "SELECT score, lines, max_combo AS maxCombo, moves, duration_s AS durationS, played_at AS playedAt FROM scores WHERE player_id = ? ORDER BY played_at DESC LIMIT 10",
  ).bind(player.id).all()
  return json({
    ok: true, tag: player.tag, best: player.best, games: player.games, createdAt: player.created_at,
    rank: await rankOf(env, player.best), recent: recent.results,
  })
}

async function submitScore(req: Request, env: Env): Promise<Response> {
  const body = await readJson(req)
  const player = await playerByToken(env, body?.token)
  if (!player) return fail(401, "Unknown token")

  const score = int(body?.score, 0, MAX_SCORE)
  const lines = int(body?.lines, 0, 100_000) ?? 0
  const maxCombo = int(body?.maxCombo, 0, 10_000) ?? 0
  const moves = int(body?.moves, 1, 100_000)
  const durationS = int(body?.durationS, 0, 7 * 86400) ?? 0
  if (score === null || moves === null) return fail(400, "Bad score")
  // A move places at most 9 blocks and clears at most 4 lines; a combo can
  // never exceed the number of moves. This is a plausibility check, not a
  // wall: an honest run is always well inside it.
  if (score > moves * (320 + 100 * moves)) return fail(400, "Score does not add up")

  const ts = now()
  const personalBest = score > player.best
  const best = Math.max(player.best, score)
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO scores (player_id, score, lines, max_combo, moves, duration_s, played_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
    ).bind(player.id, score, lines, maxCombo, moves, durationS, ts),
    env.DB.prepare("UPDATE players SET best = ?, games = games + 1, last_seen = ? WHERE id = ?").bind(best, ts, player.id),
  ])

  const [rank, dayRank, players] = await Promise.all([
    rankOf(env, best),
    env.DB.prepare(
      "SELECT COUNT(*) AS n FROM (SELECT MAX(score) AS m FROM scores WHERE played_at >= ? GROUP BY player_id) WHERE m > ?",
    ).bind(ts - 86400, score).first<{ n: number }>().then((r) => (r?.n ?? 0) + 1),
    env.DB.prepare("SELECT COUNT(*) AS n FROM players WHERE games > 0").first<{ n: number }>().then((r) => r?.n ?? 0),
  ])
  return json({ ok: true, score, best, personalBest, rank, dayRank, players })
}

async function leaderboard(url: URL, env: Env): Promise<Response> {
  const period = url.searchParams.get("period") ?? "all"
  if (!(period in PERIODS)) return fail(400, "period must be all, week or day")
  const limit = int(url.searchParams.get("limit") ?? 25, 1, 100) ?? 25
  const since = PERIODS[period] ? now() - PERIODS[period] : 0

  const rows = await env.DB.prepare(
    `SELECT p.tag AS tag, MAX(s.score) AS score, s.lines AS lines, s.max_combo AS maxCombo, s.played_at AS playedAt
       FROM scores s JOIN players p ON p.id = s.player_id
      WHERE s.played_at >= ?
      GROUP BY s.player_id
      ORDER BY score DESC, playedAt ASC
      LIMIT ?`,
  ).bind(since, limit).all()

  const totals = await env.DB.prepare(
    "SELECT COUNT(*) AS games, COUNT(DISTINCT player_id) AS players FROM scores WHERE played_at >= ?",
  ).bind(since).first<{ games: number; players: number }>()

  const entries = rows.results.map((r, i) => ({ rank: i + 1, ...r }))
  return json({ ok: true, period, entries, players: totals?.players ?? 0, games: totals?.games ?? 0, generatedAt: now() })
}

// ----------------------------------------------------------------- page

const PAGE = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Blast · scoreboard</title>
<style>
:root{color-scheme:dark;--bg:#0f1115;--fg:#e8e6e3;--dim:#8a8f98;--line:#232730;--a:#ff5c8a;--b:#ffb454;--c:#7ad0ff;--d:#7cf29b}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}
main{max-width:720px;margin:0 auto;padding:48px 20px 80px}
h1{font-size:40px;letter-spacing:-.03em;margin:0;display:flex;gap:14px;align-items:center}
.logo{display:grid;grid-template-columns:repeat(3,10px);gap:3px}.logo i{width:10px;height:10px;border-radius:2px;display:block}
.sub{color:var(--dim);margin:6px 0 28px}
nav{display:flex;gap:8px;margin-bottom:18px}nav button{background:none;border:1px solid var(--line);color:var(--dim);padding:6px 14px;border-radius:999px;cursor:pointer;font:inherit}
nav button.on{color:var(--fg);border-color:var(--fg)}
table{width:100%;border-collapse:collapse}td,th{padding:10px 8px;border-bottom:1px solid var(--line);text-align:left}th{color:var(--dim);font-weight:normal;font-size:12px;letter-spacing:.08em;text-transform:uppercase}
td.n{color:var(--dim);width:48px}td.s{text-align:right;font-variant-numeric:tabular-nums;font-weight:600}
tr:nth-child(1) td.n{color:var(--b)}tr:nth-child(2) td.n{color:var(--c)}tr:nth-child(3) td.n{color:var(--a)}
.meta{color:var(--dim);font-size:13px;margin-top:14px}.empty{color:var(--dim);padding:40px 0;text-align:center}
footer{margin-top:48px;color:var(--dim);font-size:13px}code{background:var(--line);padding:2px 6px;border-radius:4px}
a{color:var(--c)}
</style></head><body><main>
<h1><span class="logo"><i style="background:var(--a)"></i><i style="background:var(--b)"></i><i style="background:var(--c)"></i><i style="background:var(--d)"></i><i style="background:var(--a)"></i><i style="background:var(--b)"></i><i style="background:var(--c)"></i><i style="background:var(--d)"></i><i style="background:var(--a)"></i></span>Blast</h1>
<p class="sub">Block puzzle for Omarchy. Vim keys. Everyone's best runs, right here.</p>
<nav><button data-p="all" class="on">All time</button><button data-p="week">This week</button><button data-p="day">Today</button></nav>
<div id="board"></div>
<footer>Play it: <code>omarchy plugin add https://github.com/ryanyogan/omarchy-blockblast.git</code> then launch <b>Blast</b> from the app menu.</footer>
</main>
<script>
const board=document.getElementById('board');const fmt=n=>Number(n).toLocaleString();
const ago=t=>{const s=Math.floor(Date.now()/1000-t);if(s<60)return'just now';if(s<3600)return Math.floor(s/60)+'m ago';if(s<86400)return Math.floor(s/3600)+'h ago';return Math.floor(s/86400)+'d ago'}
async function load(p){board.innerHTML='<p class="empty">Loading…</p>';const r=await fetch('/v1/leaderboard?period='+p+'&limit=50');const d=await r.json();
if(!d.entries.length){board.innerHTML='<p class="empty">No runs yet. Be the first.</p>';return}
board.innerHTML='<table><tr><th>#</th><th>Player</th><th>Lines</th><th>Combo</th><th>When</th><th style="text-align:right">Score</th></tr>'+d.entries.map(e=>'<tr><td class="n">'+e.rank+'</td><td>'+e.tag.replace(/[<>&]/g,c=>({'<':'&lt;','>':'&gt;','&':'&amp;'}[c]))+'</td><td>'+e.lines+'</td><td>x'+e.maxCombo+'</td><td>'+ago(e.playedAt)+'</td><td class="s">'+fmt(e.score)+'</td></tr>').join('')+'</table><p class="meta">'+d.players+' players · '+d.games+' games</p>'}
document.querySelectorAll('nav button').forEach(b=>b.onclick=()=>{document.querySelectorAll('nav button').forEach(x=>x.classList.remove('on'));b.classList.add('on');load(b.dataset.p)});load('all');
</script></body></html>`

// ----------------------------------------------------------------- dispatch

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url)
    const path = url.pathname.replace(/\/+$/, "") || "/"
    const method = req.method.toUpperCase()

    if (method === "OPTIONS") return new Response(null, { status: 204, headers: CORS })

    try {
      if (path === "/" && method === "GET")
        return new Response(PAGE, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=60" } })
      if (path === "/v1/health") return json({ ok: true, time: now() })
      if (path === "/v1/players" && method === "POST") return registerPlayer(req, env)
      if (path === "/v1/players" && method === "DELETE") return deletePlayer(req, env)
      if (path === "/v1/players/verify" && method === "POST") return verifyPlayer(req, env)
      if (path.startsWith("/v1/players/") && method === "GET") return getPlayer(decodeURIComponent(path.slice("/v1/players/".length)), env)
      if (path === "/v1/scores" && method === "POST") return submitScore(req, env)
      if (path === "/v1/leaderboard" && method === "GET") return leaderboard(url, env)
      return fail(404, "Not found")
    } catch (e) {
      return fail(500, "Something broke", { detail: String((e as Error).message ?? e) })
    }
  },
} satisfies ExportedHandler<Env>
