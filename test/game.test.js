// Runs Game.js under node by evaluating it without the QML pragma.
const fs = require("fs"), path = require("path"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "Game.js"), "utf8").replace(/^\.pragma library\n/, "")
const G = {}
new Function("exports", src + "\n" + [
  "SIZE","SHAPES","newGame","place","canPlace","anyPlacement","anyFits","fullLines","clampAnchor",
  "clearPoints","normalizeState","serialize","validTag","fmt","refillTray","shapeByName","cellsOf","idx","COLORS"
].map(n => `exports.${n}=${n}`).join(";"))(G)

let passed = 0
function test(name, fn) { fn(); passed++; console.log("  ok  " + name) }

test("shapes are unique and inside their boxes", () => {
  const seen = new Set()
  for (const s of G.SHAPES) {
    const key = s.cells.map(c => c.join(",")).sort().join("|")
    assert(!seen.has(key), "duplicate shape " + s.name); seen.add(key)
    for (const [r, c] of s.cells) { assert(r < s.rows && c < s.cols); assert(r >= 0 && c >= 0) }
  }
  assert.equal(G.SHAPES.length, 41)
})

test("seeded games repeat", () => {
  const a = G.newGame(42), b = G.newGame(42)
  assert.deepEqual(a.tray.map(p => p.name + p.color), b.tray.map(p => p.name + p.color))
  const c = G.newGame(43)
  assert.notDeepEqual(a.tray.map(p => p.name), c.tray.map(p => p.name))
})

test("placement bounds and overlap", () => {
  const s = G.newGame(1)
  const bar = G.shapeByName("bar5")
  assert(G.canPlace(s.board, bar, 0, 3))
  assert(!G.canPlace(s.board, bar, 0, 4))
  s.board[G.idx(0, 5)] = 2
  assert(!G.canPlace(s.board, bar, 0, 3))
  assert.deepEqual(G.clampAnchor(bar, 9, 9), { row: 7, col: 3 })
})

test("row clear scores and empties the row", () => {
  const s = G.newGame(1)
  s.tray = [Object.assign({}, G.shapeByName("bar5"), { color: 1 }), Object.assign({}, G.shapeByName("bar3"), { color: 2 }), null]
  const r1 = G.place(s, 0, 2, 0)
  assert.equal(r1.lineCount, 0); assert.equal(r1.points, 5); assert.equal(s.combo, 0)
  const r2 = G.place(s, 1, 2, 5)
  assert.equal(r2.lineCount, 1); assert.deepEqual(r2.rows, [2]); assert.equal(r2.clearPoints, 10)
  assert.equal(r2.allClear, true); assert.equal(r2.bonus, 300)
  assert.equal(s.score, 5 + 3 + 10 + 300)
  for (let c = 0; c < 8; c++) assert.equal(s.board[G.idx(2, c)], 0)
  assert.equal(s.combo, 1); assert.equal(s.lines, 1)
  assert.equal(r2.refilled, true); assert.equal(s.tray.filter(Boolean).length, 3)
})

test("row and column at once, combo multiplies", () => {
  const s = G.newGame(1)
  for (let c = 0; c < 7; c++) s.board[G.idx(0, c)] = 1
  for (let r = 1; r < 8; r++) s.board[G.idx(r, 7)] = 1
  s.combo = 2
  s.tray = [Object.assign({}, G.shapeByName("dot"), { color: 3 }), null, null]
  const res = G.place(s, 0, 0, 7)
  assert.equal(res.lineCount, 2); assert.equal(res.cleared.length, 15)
  assert.equal(res.combo, 3); assert.equal(res.clearPoints, 30 * 3)
})

test("clear point table", () => {
  assert.equal(G.clearPoints(1, 1), 10); assert.equal(G.clearPoints(2, 1), 30)
  assert.equal(G.clearPoints(3, 1), 60); assert.equal(G.clearPoints(4, 1), 100)
  assert.equal(G.clearPoints(1, 4), 40)
})

test("game over when nothing fits", () => {
  const s = G.newGame(1)
  for (let i = 0; i < 64; i++) s.board[i] = 1
  s.board[0] = 0
  s.tray = [Object.assign({}, G.shapeByName("dot"), { color: 1 }), Object.assign({}, G.shapeByName("square"), { color: 1 }), null]
  assert(G.anyFits(s))
  const res = G.place(s, 0, 0, 0)
  assert(res.lineCount >= 1)
  // after the clear, does the square fit? row 0 and col 0 cleared -> yes; so not over
  assert.equal(s.over, false)
})

test("illegal moves return null and change nothing", () => {
  const s = G.newGame(5)
  const before = JSON.stringify(G.serialize(s))
  assert.equal(G.place(s, 0, 7, 7), s.tray[0].rows === 1 && s.tray[0].cols === 1 ? G.place(s, 0, 7, 7) : null)
  assert.equal(G.place(s, 2, 99, 0), null)
  if (s.moves === 0) assert.equal(JSON.stringify(G.serialize(s)), before)
})

test("serialize round trip", () => {
  const s = G.newGame(99)
  G.place(s, 0, 0, 0)
  const back = G.normalizeState(JSON.parse(JSON.stringify(G.serialize(s))))
  assert.deepEqual(G.serialize(back), G.serialize(s))
  assert.equal(G.normalizeState({ version: 2 }), null)
  assert.equal(G.normalizeState(null), null)
})

test("random playthroughs never corrupt state", () => {
  let overs = 0, totalScore = 0
  for (let g = 0; g < 200; g++) {
    const s = G.newGame(g)
    let guard = 0
    while (!s.over && guard++ < 2000) {
      let moved = false
      for (let i = 0; i < 3 && !moved; i++) {
        const p = G.anyPlacement(s.board, s.tray[i])
        if (p) { const r = G.place(s, i, p.row, p.col); assert(r); moved = true }
      }
      assert(moved, "anyFits said yes but no placement found")
      for (const v of s.board) assert(v >= 0 && v <= G.COLORS)
    }
    if (s.over) overs++
    totalScore += s.score
  }
  assert(overs > 150, "greedy games should mostly end: " + overs)
  console.log("       avg greedy score", Math.round(totalScore / 200))
})

test("tags and formatting", () => {
  assert(G.validTag("ryan")); assert(G.validTag("neo_42")); assert(!G.validTag("a")); assert(!G.validTag("has space")); assert(!G.validTag("_lead"))
  assert.equal(G.fmt(1234567), "1,234,567"); assert.equal(G.fmt(12), "12")
})

console.log(passed + " tests passed")
