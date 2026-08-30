.pragma library

// Blast: the rules of the game, with nothing visual in it.
//
// An 8x8 board. Three pieces on the tray. Place a piece anywhere it fits; when
// all three are down, three more arrive. Full rows and columns clear at once,
// with no gravity. The game ends when nothing on the tray fits anywhere.
//
// Every function here is pure or works on the plain state object it is given,
// so the same file runs under node for tests (see test/game.test.js) and under
// the QML engine for the overlay.

var SIZE = 8
var TRAY = 3

// ----------------------------------------------------------------- pieces

// Each shape is a list of [row, col] cells with its own bounding box. `w` is a
// draw weight: the classic game hands out small and medium pieces more often
// than the 3x3 or the five-long bar.
function shape(name, cells, w) {
  var rows = 0, cols = 0
  for (var i = 0; i < cells.length; i++) {
    rows = Math.max(rows, cells[i][0] + 1)
    cols = Math.max(cols, cells[i][1] + 1)
  }
  return { name: name, cells: cells, rows: rows, cols: cols, w: w }
}

function rotations(name, cells, w, count) {
  var out = []
  var seen = {}
  var cur = cells
  for (var r = 0; r < count; r++) {
    var s = shape(name + (r ? "-r" + r : ""), normalize(cur), w)
    var key = s.cells.map(function(c) { return c.join(",") }).sort().join("|")
    if (!seen[key]) { seen[key] = true; out.push(s) }
    cur = rotate(cur)
  }
  return out
}

function rotate(cells) {
  var maxRow = 0
  for (var i = 0; i < cells.length; i++) maxRow = Math.max(maxRow, cells[i][0])
  return cells.map(function(c) { return [c[1], maxRow - c[0]] })
}

function normalize(cells) {
  var minR = Infinity, minC = Infinity
  for (var i = 0; i < cells.length; i++) { minR = Math.min(minR, cells[i][0]); minC = Math.min(minC, cells[i][1]) }
  return cells.map(function(c) { return [c[0] - minR, c[1] - minC] })
    .sort(function(a, b) { return a[0] - b[0] || a[1] - b[1] })
}

function line(n, horizontal) {
  var cells = []
  for (var i = 0; i < n; i++) cells.push(horizontal ? [0, i] : [i, 0])
  return cells
}

function rect(r, c) {
  var cells = []
  for (var i = 0; i < r; i++) for (var j = 0; j < c; j++) cells.push([i, j])
  return cells
}

var SHAPES = [].concat(
  [shape("dot", rect(1, 1), 7)],
  [shape("bar2", line(2, true), 9), shape("bar2v", line(2, false), 9)],
  [shape("bar3", line(3, true), 9), shape("bar3v", line(3, false), 9)],
  [shape("bar4", line(4, true), 6), shape("bar4v", line(4, false), 6)],
  [shape("bar5", line(5, true), 3), shape("bar5v", line(5, false), 3)],
  [shape("square", rect(2, 2), 10)],
  [shape("big", rect(3, 3), 2)],
  [shape("slab", rect(2, 3), 4), shape("slabv", rect(3, 2), 4)],
  rotations("elbow", [[0, 0], [1, 0], [1, 1]], 8, 4),
  rotations("ell", [[0, 0], [1, 0], [2, 0], [2, 1]], 5, 4),
  rotations("jay", [[0, 1], [1, 1], [2, 1], [2, 0]], 5, 4),
  rotations("corner", [[0, 0], [1, 0], [2, 0], [2, 1], [2, 2]], 3, 4),
  rotations("tee", [[0, 0], [0, 1], [0, 2], [1, 1]], 5, 4),
  rotations("ess", [[0, 1], [0, 2], [1, 0], [1, 1]], 4, 2),
  rotations("zed", [[0, 0], [0, 1], [1, 1], [1, 2]], 4, 2),
  rotations("diag2", [[0, 0], [1, 1]], 2, 2),
  rotations("diag3", [[0, 0], [1, 1], [2, 2]], 1, 2)
)

var TOTAL_WEIGHT = SHAPES.reduce(function(sum, s) { return sum + s.w }, 0)

function shapeByName(name) {
  for (var i = 0; i < SHAPES.length; i++) if (SHAPES[i].name === name) return SHAPES[i]
  return null
}

// ----------------------------------------------------------------- rng

// mulberry32. Small, fast, and the whole generator state is one integer, so
// a game in progress can be written to disk and continue with the same
// sequence of pieces after a restart.
function rngNext(state) {
  var t = (state.rng + 0x6D2B79F5) | 0
  state.rng = t
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}

function rngInt(state, n) { return Math.floor(rngNext(state) * n) }

function drawShape(state) {
  var roll = rngNext(state) * TOTAL_WEIGHT
  for (var i = 0; i < SHAPES.length; i++) {
    roll -= SHAPES[i].w
    if (roll < 0) return SHAPES[i]
  }
  return SHAPES[SHAPES.length - 1]
}

// ----------------------------------------------------------------- state

var COLORS = 7

function emptyBoard() {
  var b = []
  for (var i = 0; i < SIZE * SIZE; i++) b.push(0)
  return b
}

function newGame(seed) {
  var s = {
    version: 1,
    seed: seed === undefined ? (Date.now() & 0x7fffffff) : (seed | 0),
    rng: 0,
    board: emptyBoard(),
    tray: [null, null, null],
    score: 0,
    lines: 0,
    combo: 0,
    maxCombo: 0,
    moves: 0,
    startedAt: Date.now(),
    playedMs: 0,
    over: false
  }
  s.rng = s.seed
  refillTray(s)
  return s
}

function pieceFromShape(shape, color) {
  return { name: shape.name, cells: shape.cells, rows: shape.rows, cols: shape.cols, color: color }
}

// Three fresh pieces. The classic game will happily hand you a tray nothing
// on it fits and end your run; here the first few rerolls give it a chance to
// find a playable set, so the ending comes from the board and not from the
// dice. After that it lets the tray stand and the game ends honestly.
function refillTray(s) {
  for (var attempt = 0; attempt < 6; attempt++) {
    var tray = []
    for (var i = 0; i < TRAY; i++) tray.push(pieceFromShape(drawShape(s), 1 + rngInt(s, COLORS)))
    s.tray = tray
    if (attempt === 5 || anyFits(s)) return
  }
}

function trayEmpty(s) {
  for (var i = 0; i < s.tray.length; i++) if (s.tray[i]) return false
  return true
}

function trayCount(s) {
  var n = 0
  for (var i = 0; i < s.tray.length; i++) if (s.tray[i]) n++
  return n
}

// ----------------------------------------------------------------- placement

function idx(r, c) { return r * SIZE + c }

function canPlace(board, piece, row, col) {
  if (!piece) return false
  if (row < 0 || col < 0 || row + piece.rows > SIZE || col + piece.cols > SIZE) return false
  for (var i = 0; i < piece.cells.length; i++) {
    if (board[idx(row + piece.cells[i][0], col + piece.cells[i][1])]) return false
  }
  return true
}

function anyPlacement(board, piece) {
  if (!piece) return null
  for (var r = 0; r + piece.rows <= SIZE; r++)
    for (var c = 0; c + piece.cols <= SIZE; c++)
      if (canPlace(board, piece, r, c)) return { row: r, col: c }
  return null
}

function anyFits(s) {
  for (var i = 0; i < s.tray.length; i++) if (anyPlacement(s.board, s.tray[i])) return true
  return false
}

// Clamp a wanted anchor so the piece stays on the board. Movement keys call
// this, so a wide piece near the right edge just stops instead of vanishing.
function clampAnchor(piece, row, col) {
  var maxR = piece ? SIZE - piece.rows : SIZE - 1
  var maxC = piece ? SIZE - piece.cols : SIZE - 1
  return { row: Math.max(0, Math.min(maxR, row)), col: Math.max(0, Math.min(maxC, col)) }
}

// Rows and columns that would be full if `cells` were filled, as they would
// be after a placement. Used for the live preview and for the real clear.
function fullLines(board, extraCells) {
  // Fill counts per row and column; the extra cells (a piece preview) are
  // added on top without copying the board. Runs on every cursor move.
  var rowN = [0, 0, 0, 0, 0, 0, 0, 0]
  var colN = [0, 0, 0, 0, 0, 0, 0, 0]
  for (var i = 0; i < SIZE * SIZE; i++) {
    if (board[i]) { rowN[(i / SIZE) | 0]++; colN[i % SIZE]++ }
  }
  if (extraCells) {
    for (var e = 0; e < extraCells.length; e++) {
      var cell = extraCells[e]
      if (!board[cell]) { rowN[(cell / SIZE) | 0]++; colN[cell % SIZE]++ }
    }
  }
  var rows = [], cols = []
  for (var r = 0; r < SIZE; r++) if (rowN[r] === SIZE) rows.push(r)
  for (var c = 0; c < SIZE; c++) if (colN[c] === SIZE) cols.push(c)
  return { rows: rows, cols: cols }
}

function cellsOf(piece, row, col) {
  var out = []
  for (var i = 0; i < piece.cells.length; i++) out.push(idx(row + piece.cells[i][0], col + piece.cells[i][1]))
  return out
}

// ----------------------------------------------------------------- scoring

// Placing earns a point per block. Clearing pays 10 for one line, and each
// extra line in the same move is worth more than the last (30 for two, 60 for
// three, 100 for four). Consecutive clearing moves build a combo that
// multiplies the clear. Emptying the whole board is worth a flat 300 on top.
function clearPoints(lineCount, combo) {
  if (lineCount <= 0) return 0
  var base = 10 * lineCount * (lineCount + 1) / 2
  return base * Math.max(1, combo)
}

var ALL_CLEAR_BONUS = 300

// Place tray slot `slot` at (row, col). Mutates `s` and returns a description
// of what happened, or null if the move was illegal. The result feeds the
// animations: which cells landed, which lines cleared, how many points, and
// whether the tray was refilled.
function place(s, slot, row, col) {
  var piece = s.tray[slot]
  if (!piece || s.over || !canPlace(s.board, piece, row, col)) return null

  var landed = cellsOf(piece, row, col)
  for (var i = 0; i < landed.length; i++) s.board[landed[i]] = piece.color

  var lines = fullLines(s.board, null)
  var lineCount = lines.rows.length + lines.cols.length
  var cleared = []
  var clearedSet = {}
  for (var r = 0; r < lines.rows.length; r++)
    for (var c = 0; c < SIZE; c++) { var k = idx(lines.rows[r], c); if (!clearedSet[k]) { clearedSet[k] = true; cleared.push(k) } }
  for (var cc = 0; cc < lines.cols.length; cc++)
    for (var rr = 0; rr < SIZE; rr++) { var k2 = idx(rr, lines.cols[cc]); if (!clearedSet[k2]) { clearedSet[k2] = true; cleared.push(k2) } }

  var clearedColors = {}
  for (var j = 0; j < cleared.length; j++) { clearedColors[cleared[j]] = s.board[cleared[j]]; s.board[cleared[j]] = 0 }

  if (lineCount > 0) s.combo += 1
  else s.combo = 0
  s.maxCombo = Math.max(s.maxCombo, s.combo)

  var placePts = landed.length
  var clearPts = clearPoints(lineCount, s.combo)
  var allClear = false
  if (lineCount > 0) {
    allClear = true
    for (var b = 0; b < s.board.length; b++) if (s.board[b]) { allClear = false; break }
  }
  var bonus = allClear ? ALL_CLEAR_BONUS : 0

  s.score += placePts + clearPts + bonus
  s.lines += lineCount
  s.moves += 1
  s.tray[slot] = null

  var refilled = false
  if (trayEmpty(s)) { refillTray(s); refilled = true }
  s.over = !anyFits(s)

  return {
    slot: slot,
    piece: piece,
    row: row,
    col: col,
    landed: landed,
    rows: lines.rows,
    cols: lines.cols,
    cleared: cleared,
    clearedColors: clearedColors,
    lineCount: lineCount,
    combo: s.combo,
    placePoints: placePts,
    clearPoints: clearPts,
    bonus: bonus,
    points: placePts + clearPts + bonus,
    allClear: allClear,
    refilled: refilled,
    over: s.over
  }
}

// ----------------------------------------------------------------- persistence

// Turn whatever came off disk into a state the rest of this file trusts.
function normalizeState(raw) {
  if (!raw || typeof raw !== "object" || raw.version !== 1) return null
  var s = newGame(0)
  if (!Array.isArray(raw.board) || raw.board.length !== SIZE * SIZE) return null
  s.seed = raw.seed | 0
  s.rng = raw.rng | 0
  s.board = raw.board.map(function(v) { v = v | 0; return v < 0 || v > COLORS ? 0 : v })
  s.tray = [null, null, null]
  if (Array.isArray(raw.tray)) {
    for (var i = 0; i < TRAY; i++) {
      var p = raw.tray[i]
      var sh = p && shapeByName(String(p.name))
      if (sh) s.tray[i] = pieceFromShape(sh, Math.max(1, Math.min(COLORS, p.color | 0)))
    }
  }
  s.score = Math.max(0, raw.score | 0)
  s.lines = Math.max(0, raw.lines | 0)
  s.combo = Math.max(0, raw.combo | 0)
  s.maxCombo = Math.max(s.combo, raw.maxCombo | 0)
  s.moves = Math.max(0, raw.moves | 0)
  s.startedAt = Number(raw.startedAt) || Date.now()
  s.playedMs = Math.max(0, Number(raw.playedMs) || 0)
  s.over = raw.over === true || !anyFits(s)
  if (trayEmpty(s) && !s.over) refillTray(s)
  return s
}

function serialize(s) {
  return {
    version: 1, seed: s.seed, rng: s.rng, board: s.board,
    tray: s.tray.map(function(p) { return p ? { name: p.name, color: p.color } : null }),
    score: s.score, lines: s.lines, combo: s.combo, maxCombo: s.maxCombo, moves: s.moves,
    startedAt: s.startedAt, playedMs: s.playedMs, over: s.over
  }
}

// ----------------------------------------------------------------- gamer tags

var TAG_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{1,15}$/
function validTag(tag) { return TAG_RE.test(String(tag || "")) }

function fmt(n) {
  n = Math.round(Number(n) || 0)
  var s = String(Math.abs(n))
  var out = ""
  while (s.length > 3) { out = "," + s.slice(-3) + out; s = s.slice(0, -3) }
  return (n < 0 ? "-" : "") + s + out
}
