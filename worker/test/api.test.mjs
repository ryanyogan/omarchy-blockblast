// End-to-end against a running `wrangler dev` (default http://localhost:8787).
import assert from "node:assert"
const BASE = process.env.BLAST_API || "http://localhost:8787"
const call = async (method, path, body) => {
  const r = await fetch(BASE + path, { method, headers: { "content-type": "application/json" }, body: body ? JSON.stringify(body) : undefined })
  return { status: r.status, body: await r.json() }
}
const tag = "t" + Math.random().toString(36).slice(2, 10)
let n = 0
const ok = (name) => { n++; console.log("  ok  " + name) }

let r = await call("GET", "/v1/health"); assert.equal(r.status, 200); ok("health")

r = await call("POST", "/v1/players", { tag: "x" }); assert.equal(r.status, 400); ok("rejects short tag")
r = await call("POST", "/v1/players", { tag: "no spaces" }); assert.equal(r.status, 400); ok("rejects bad tag")
r = await call("POST", "/v1/players", { tag }); assert.equal(r.status, 201); const token = r.body.token; assert(token.length > 20); ok("registers " + tag)
r = await call("POST", "/v1/players", { tag: tag.toUpperCase() }); assert.equal(r.status, 409); ok("tags unique case-insensitively")

r = await call("POST", "/v1/players/verify", { token: "nope-nope-nope-nope" }); assert.equal(r.status, 401); ok("verify rejects bad token")
r = await call("POST", "/v1/players/verify", { token }); assert.equal(r.status, 200); assert.equal(r.body.tag, tag); assert.equal(r.body.games, 0); ok("verify")

r = await call("POST", "/v1/scores", { token, score: 999999, moves: 2 }); assert.equal(r.status, 400); ok("implausible score rejected")
r = await call("POST", "/v1/scores", { token, score: 1200, lines: 9, maxCombo: 3, moves: 40, durationS: 300 })
assert.equal(r.status, 200); assert.equal(r.body.personalBest, true); assert.equal(r.body.best, 1200); assert(r.body.rank >= 1); ok("submit score rank " + r.body.rank)
r = await call("POST", "/v1/scores", { token, score: 400, lines: 2, maxCombo: 1, moves: 20, durationS: 100 })
assert.equal(r.body.personalBest, false); assert.equal(r.body.best, 1200); ok("lower score keeps best")

r = await call("GET", "/v1/players/" + tag); assert.equal(r.status, 200); assert.equal(r.body.best, 1200); assert.equal(r.body.games, 2); assert.equal(r.body.recent.length, 2); ok("player profile")
r = await call("GET", "/v1/players/zzz-nobody-zzz"); assert.equal(r.status, 404); ok("unknown player 404")

for (const p of ["all", "week", "day"]) {
  r = await call("GET", "/v1/leaderboard?period=" + p + "&limit=5")
  assert.equal(r.status, 200); assert(r.body.entries.length >= 1); assert(r.body.entries.length <= 5)
  const mine = r.body.entries.find((e) => e.tag === tag)
  if (mine) assert.equal(mine.score, 1200)
  for (let i = 1; i < r.body.entries.length; i++) assert(r.body.entries[i - 1].score >= r.body.entries[i].score)
  ok("leaderboard " + p)
}
r = await call("GET", "/v1/leaderboard?period=year"); assert.equal(r.status, 400); ok("bad period")

const page = await fetch(BASE + "/"); assert.equal(page.status, 200); assert((await page.text()).includes("Blast")); ok("scoreboard page")

r = await call("DELETE", "/v1/players", { token }); assert.equal(r.status, 200)
r = await call("GET", "/v1/players/" + tag); assert.equal(r.status, 404); ok("delete player and scores")
console.log(n + " api tests passed")
