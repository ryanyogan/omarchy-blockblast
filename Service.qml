import QtQuick
import Quickshell
import Quickshell.Io
import "Game.js" as Game

// Blast service: owner of the save file and the only thing that talks to the
// leaderboard. The overlay plays the game and hands finished runs here.
//
// Idle cost is nothing: no timers, no processes, no sockets. File I/O happens
// when a move lands (debounced) and network happens when a game ends or the
// leaderboard pane opens.
//
// All real I/O runs through blast-io.py, a single-process helper that binds
// state-file access to verified descriptors, refuses untrusted URLs and
// redirects, and caps every byte it reads before this file ever parses it.
// Everything that comes back -- from the API or from disk -- is clamped to a
// fixed schema here before it is persisted or rendered.
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null

  // ---------------------------------------------------------------- state

  readonly property string ioHelper: Qt.resolvedUrl("blast-io.py").toString().replace(/^file:\/\//, "")
  readonly property int maxStateBytes: 98304

  // The API this build talks to. Overridable with BLAST_API in the shell's
  // environment or `:api URL` inside the game (saved to the state file).
  // Only https endpoints are trusted with the token; plain http is accepted
  // for localhost development only. Anything else is ignored.
  readonly property string builtinApi: "https://blockblast.yogan.dev"
  function trustedBase(url) {
    var s = String(url || "").trim().replace(/\/+$/, "")
    if (/^https:\/\/[a-zA-Z0-9]([a-zA-Z0-9.-]{0,200})?(:\d{1,5})?$/.test(s)) return s
    if (/^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d{1,5})?$/.test(s)) return s
    return ""
  }
  readonly property string apiBase: {
    var saved = trustedBase(state.apiBase)
    if (saved) return saved
    var env = trustedBase(Quickshell.env("BLAST_API"))
    return env || builtinApi
  }

  property bool stateLoaded: false
  property var state: defaultState()

  function defaultState() {
    return {
      version: 1,
      game: null,                 // serialized in-progress game, or null
      best: { score: 0, lines: 0, maxCombo: 0, at: 0 },
      history: [],                // most recent first, capped
      player: null,               // { id, tag, token }
      pending: [],                // finished games not yet posted
      apiBase: "",
      reducedMotion: false,
      leaderboardEnabled: true,
      seenIntro: false,
      scrimOpacity: 0,
      gamesPlayed: 0
    }
  }

  // Clamps for anything that arrives from disk or the network. Strings lose
  // control characters and get a hard length; numbers get a hard range.
  function capStr(v, n) {
    var s = String(v === undefined || v === null ? "" : v)
    s = s.replace(/[\u0000-\u001F\u007F-\u009F\u2028\u2029]/g, " ")
    return s.length > n ? s.slice(0, n) : s
  }
  function capInt(v, hi) {
    v = Math.floor(Number(v) || 0)
    return v < 0 ? 0 : v > hi ? hi : v
  }

  // One finished run, local or replayed off disk, reduced to exactly the
  // fields the UI knows. Anything else is dropped.
  function normRecord(h) {
    if (!h || typeof h !== "object") return null
    return {
      score: capInt(h.score, 1e9), lines: capInt(h.lines, 1e6), maxCombo: capInt(h.maxCombo, 1e6),
      moves: capInt(h.moves, 1e6), durationS: capInt(h.durationS, 1e9), at: capInt(h.at, 1e14),
      seed: h.seed | 0, posted: h.posted === true, rank: capInt(h.rank, 1e9),
      dayRank: capInt(h.dayRank, 1e9), personalBest: h.personalBest === true
    }
  }

  function normalize(raw) {
    var s = defaultState()
    if (!raw || typeof raw !== "object") return s
    if (raw.game && typeof raw.game === "object") {
      // Round-trip through the game's own normalizer so a doctored save can
      // never persist more than one bounded board.
      var g = Game.normalizeState(raw.game)
      s.game = g ? Game.serialize(g) : null
    }
    if (raw.best && typeof raw.best === "object") {
      s.best = { score: capInt(raw.best.score, 1e9), lines: capInt(raw.best.lines, 1e6),
                 maxCombo: capInt(raw.best.maxCombo, 1e6), at: capInt(raw.best.at, 1e14) }
    }
    if (Array.isArray(raw.history)) s.history = raw.history.map(normRecord).filter(function(h) { return !!h }).slice(0, 50)
    if (raw.player && typeof raw.player === "object" && typeof raw.player.token === "string"
        && raw.player.token.length > 0 && raw.player.token.length <= 512 && Game.validTag(raw.player.tag))
      s.player = { id: capStr(raw.player.id, 64), tag: String(raw.player.tag), token: String(raw.player.token) }
    if (Array.isArray(raw.pending)) s.pending = raw.pending.map(normRecord).filter(function(p) { return !!p }).slice(0, 50)
    s.apiBase = trustedBase(raw.apiBase)
    s.reducedMotion = raw.reducedMotion === true
    s.leaderboardEnabled = raw.leaderboardEnabled !== false
    s.seenIntro = raw.seenIntro === true
    var so = Number(raw.scrimOpacity)
    s.scrimOpacity = isFinite(so) && so > 0 ? Math.max(0.2, Math.min(1, so)) : 0
    s.gamesPlayed = capInt(raw.gamesPlayed, 1e9)
    return s
  }

  // Every mutation goes through here so bindings on `state` re-evaluate
  // (reassigning the property is what QML notices) and a save is queued.
  function update(mutator) {
    var next = normalize(JSON.parse(JSON.stringify(state)))
    mutator(next)
    state = next
    saveSoon()
  }

  readonly property var player: state.player
  readonly property bool hasTag: !!(state.player && state.player.tag)
  readonly property string tag: hasTag ? state.player.tag : ""
  readonly property int bestScore: state.best ? state.best.score : 0
  readonly property bool reducedMotion: state.reducedMotion === true
  // Off means off: no posting, no fetching, no verifying. Nothing leaves.
  readonly property bool leaderboardEnabled: state.leaderboardEnabled !== false
  readonly property bool seenIntro: state.seenIntro === true
  // 0 means "use the theme default". Otherwise 0.2..1.
  readonly property real scrimOpacity: Number(state.scrimOpacity) || 0
  readonly property var savedGame: state.game

  // ---------------------------------------------------------------- game hooks

  function openOverlay() { if (shell && typeof shell.toggle === "function") shell.toggle("ryanyogan.blast", "{}") }

  function saveGame(serialized) { update(function(s) { s.game = serialized }) }
  function clearGame() { update(function(s) { s.game = null }) }
  function setReducedMotion(on) { update(function(s) { s.reducedMotion = on === true }) }
  function setLeaderboardEnabled(on) { update(function(s) { s.leaderboardEnabled = on === true; if (!s.leaderboardEnabled) s.pending = [] }) }
  function markIntroSeen() { update(function(s) { s.seenIntro = true }) }
  function setScrimOpacity(v) { update(function(s) { s.scrimOpacity = v }) }
  // Returns false when the URL fails the trust policy; nothing is saved then.
  function setApiBase(url) {
    var clean = String(url || "").trim()
    if (clean && !trustedBase(clean)) return false
    update(function(s) { s.apiBase = clean ? root.trustedBase(clean) : "" })
    return true
  }

  // A finished run. Records it locally, then posts it if there is a tag.
  // Returns the local record so the overlay can show it right away.
  function finishGame(game, cb) {
    var rec = {
      score: game.score | 0, lines: game.lines | 0, maxCombo: game.maxCombo | 0, moves: game.moves | 0,
      durationS: Math.round((game.playedMs || 0) / 1000), at: Date.now(), seed: game.seed | 0,
      posted: false, rank: 0, dayRank: 0, personalBest: false
    }
    var isBest = rec.score > bestScore
    update(function(s) {
      s.game = null
      s.gamesPlayed += 1
      if (isBest) s.best = { score: rec.score, lines: rec.lines, maxCombo: rec.maxCombo, at: rec.at }
      s.history = [rec].concat(s.history).slice(0, 50)
      if (s.player && s.leaderboardEnabled && rec.moves > 0) s.pending = s.pending.concat([rec])
    })
    rec.localBest = isBest
    if (hasTag && leaderboardEnabled && rec.moves > 0) flushPending(cb)
    else if (cb) cb(rec, null)
    return rec
  }

  // ---------------------------------------------------------------- network

  property bool busy: false
  property string lastError: ""

  // Requests run one at a time through the helper process. Each one gets a
  // hard deadline here on top of the helper's own socket timeout, and the
  // helper is a single process, so killing it leaves nothing behind.
  property var netQueue: []
  property bool netBusy: false

  function request(method, path, body, cb) {
    if (!leaderboardEnabled) { cb(null, "Leaderboard is off"); return }
    if (netQueue.length >= 8) { cb(null, "Busy"); return }
    netQueue.push({ method: method, path: path, body: body, cb: cb })
    pumpNet()
  }

  function pumpNet() {
    if (netBusy || netProc.running || dead) return
    if (!netQueue.length) return
    var req = netQueue.shift()
    netBusy = true
    netProc.req = req
    netProc.environment = ({ BLAST_BODY: req.body === undefined ? "" : JSON.stringify(req.body) })
    netProc.command = ["/usr/bin/python3", ioHelper, "request", req.method, apiBase + req.path]
    netDeadline.restart()
    netProc.running = true
  }

  Process {
    id: netProc
    property var req: null
    running: false
    stdout: StdioCollector { id: netOut; waitForEnd: true }
    stderr: StdioCollector { id: netErr; waitForEnd: true }
    onExited: function(code, status) {
      netDeadline.stop()
      var req = netProc.req
      netProc.req = null
      root.netBusy = false
      if (req && req.cb) {
        if (code === 0) {
          var text = netOut.text || ""
          var nl = text.indexOf("\n")
          var httpStatus = nl > 0 ? parseInt(text.slice(0, nl), 10) || 0 : 0
          var parsed = null
          try { parsed = nl >= 0 && text.length > nl + 1 ? JSON.parse(text.slice(nl + 1)) : null } catch (e) { parsed = null }
          if (httpStatus >= 200 && httpStatus < 300 && parsed) {
            root.lastError = ""
            req.cb(parsed, null)
          } else {
            var msg = parsed && parsed.error ? root.capStr(parsed.error, 120) : "HTTP " + httpStatus
            root.lastError = msg
            req.cb(parsed, msg)
          }
        } else if (code === 3 || code === 5) {
          var refusal = root.capStr(String(netErr.text || "").trim(), 120) || "Request refused"
          root.lastError = refusal
          req.cb(null, refusal)
        } else {
          root.lastError = "No connection"
          req.cb(null, "No connection to " + root.apiBase)
        }
      }
      root.pumpNet()
    }
  }
  Timer { id: netDeadline; interval: 12000; onTriggered: netProc.running = false }

  // Claim a gamer tag. On success the token lands in the state file and any
  // pending runs are posted under it.
  function register(tag, cb) {
    tag = String(tag || "").trim()
    if (!Game.validTag(tag)) { cb(null, "2 to 16 letters, numbers, _ or -"); return }
    busy = true
    request("POST", "/v1/players", { tag: tag }, function(res, err) {
      busy = false
      if (err || !res || typeof res.token !== "string" || !res.token) { cb(null, err || "Could not register"); return }
      // Never persist an oversized token or a tag the game itself would
      // reject; a server that sends one does not get saved.
      if (res.token.length > 512 || !Game.validTag(res.tag)) { cb(null, "The server sent an invalid registration"); return }
      var clean = { id: capStr(res.id, 64), tag: String(res.tag), token: String(res.token) }
      update(function(s) {
        s.player = clean
        // Runs finished before the tag existed are still worth posting.
        var unposted = s.history.filter(function(h) { return !h.posted && h.moves > 0 })
        s.pending = unposted.slice(0, 10)
      })
      cb(clean, null)
    })
  }

  function forget() { update(function(s) { s.player = null; s.pending = [] }) }

  // Post queued runs oldest first. Stops at the first network failure and
  // leaves the rest for next time. `cb` fires once with the newest record.
  property bool flushing: false
  function flushPending(cb) {
    if (flushing || !hasTag) { if (cb) cb(null, flushing ? "Busy" : "No tag"); return }
    var queue = state.pending.slice()
    if (!queue.length) { if (cb) cb(null, null); return }
    flushing = true
    var newest = queue[queue.length - 1]
    var lastErr = null
    var step = function() {
      if (!queue.length) {
        flushing = false
        if (cb) cb(newest, lastErr)
        return
      }
      var rec = queue[0]
      request("POST", "/v1/scores", {
        token: root.state.player.token, score: rec.score, lines: rec.lines,
        maxCombo: rec.maxCombo, moves: rec.moves, durationS: rec.durationS
      }, function(res, err) {
        if (err && (err.indexOf("No connection") === 0 || err.indexOf("HTTP 5") === 0)) {
          lastErr = err
          flushing = false
          if (cb) cb(newest, err)
          return
        }
        queue.shift()
        var ok = res && res.ok === true
        var rank = ok ? root.capInt(res.rank, 1e9) : 0
        var dayRank = ok ? root.capInt(res.dayRank, 1e9) : 0
        var personalBest = ok && res.personalBest === true
        // A 4xx means the server will never take this one; drop it.
        update(function(s) {
          s.pending = s.pending.filter(function(p) { return p.at !== rec.at })
          for (var i = 0; i < s.history.length; i++) {
            if (s.history[i].at === rec.at) {
              s.history[i].posted = !err
              if (ok) {
                s.history[i].rank = rank
                s.history[i].dayRank = dayRank
                s.history[i].personalBest = personalBest
              }
            }
          }
        })
        if (rec.at === newest.at) {
          if (ok) { newest.rank = rank; newest.dayRank = dayRank; newest.personalBest = personalBest; newest.players = root.capInt(res.players, 1e9) }
          newest.posted = !err
          lastErr = err
        }
        step()
      })
    }
    step()
  }

  function verify(cb) {
    if (!hasTag) { cb(null, "No tag"); return }
    request("POST", "/v1/players/verify", { token: state.player.token }, function(res, err) {
      if (err === "Unknown token") { forget(); cb(null, "Your tag is no longer registered"); return }
      if (err || !res) { cb(null, err); return }
      cb({ ok: res.ok === true, rank: capInt(res.rank, 1e9), best: capInt(res.best, 1e9) }, null)
    })
  }

  function leaderboard(period, limit, cb) {
    limit = Math.max(1, Math.min(100, limit | 0))
    request("GET", "/v1/leaderboard?period=" + encodeURIComponent(period) + "&limit=" + limit, undefined, function(res, err) {
      if (err || !res) { cb(null, err || "Could not load"); return }
      // The board is rebuilt entry by entry to a fixed shape and cardinality;
      // nothing the server sends reaches a model or the state file as-is.
      var out = { ok: res.ok === true, players: capInt(res.players, 1e9), games: capInt(res.games, 1e9), entries: [] }
      var arr = Array.isArray(res.entries) ? res.entries : []
      for (var i = 0; i < arr.length && out.entries.length < limit; i++) {
        var e = arr[i]
        if (!e || typeof e !== "object") continue
        out.entries.push({
          rank: capInt(e.rank, 1e9), tag: capStr(e.tag, 16), score: capInt(e.score, 1e9),
          lines: capInt(e.lines, 1e6), maxCombo: capInt(e.maxCombo, 1e6)
        })
      }
      cb(out, null)
    })
  }

  // ---------------------------------------------------------------- persistence

  property bool dead: false
  property bool saveQueued: false
  Timer { id: saveDebounce; interval: 150; onTriggered: root.saveState() }
  function saveSoon() {
    if (!stateLoaded) return
    // A fresh change after automatic retries gave up earns a fresh series.
    if (saveAttempts >= maxSaveAttempts) saveAttempts = 0
    saveDebounce.restart()
  }

  // Why the last read or write failed, or "". Both are surfaced by the
  // overlay. While saveError is set the in-memory state is newer than the
  // disk, so refresh() retries the write instead of reloading over it.
  property string loadError: ""
  property string saveError: ""

  // Write now, whatever the retry schedule says. Used by :save.
  function saveNow() { saveRetry.stop(); saveDebounce.stop(); saveState() }

  Process {
    id: stateReader
    running: false
    stdout: StdioCollector { id: readOut; waitForEnd: true }
    stderr: StdioCollector { id: readErr; waitForEnd: true }
    onExited: function(code, status) {
      readDeadline.stop()
      if (code !== 0 || status !== 0) {
        // The file exists but the helper would not vouch for it (wrong
        // owner, not a regular file, too large, or the read overran). Play
        // from defaults without saving so the file is never replaced blind.
        root.loadError = root.capStr(String(readErr.text || "").trim(), 120) || "Could not read the save"
        root.state = root.normalize(null)
        root.stateLoaded = false
        return
      }
      var parsed = null
      var text = readOut.text || ""
      try { parsed = text.trim() === "" ? null : JSON.parse(text) } catch (e) { parsed = null }
      root.state = root.normalize(parsed)
      root.loadError = ""
      root.stateLoaded = true
    }
  }
  Timer { id: readDeadline; interval: 6000; onTriggered: stateReader.running = false }

  // Re-read the file from disk. The overlay calls this on open so a save
  // edited or synced from elsewhere is what you resume.
  function refresh() {
    if (stateReader.running || stateWriter.running || saveDebounce.running) return
    if (saveError !== "" || saveRetry.running) { saveNow(); return }
    stateLoaded = false
    loadState()
  }

  function loadState() {
    if (stateReader.running) return
    stateReader.command = ["/usr/bin/python3", ioHelper, "read"]
    readDeadline.restart()
    stateReader.running = true
  }

  // A failed write is retried on its own a bounded number of times, backing
  // off 1s, 3s, 9s, 27s. After that the state stays in memory, saveError
  // stays set, and the next change, overlay open, or :save tries again.
  property int saveAttempts: 0
  readonly property int maxSaveAttempts: 5
  Timer { id: saveRetry; onTriggered: root.saveState() }

  Process {
    id: stateWriter
    running: false
    stderr: StdioCollector { id: writeErr; waitForEnd: true }
    onExited: function(code, status) {
      writeDeadline.stop()
      if (code === 0 && status === 0) {
        root.saveAttempts = 0
        root.saveError = ""
        if (root.saveQueued) { root.saveQueued = false; root.saveState() }
        return
      }
      root.saveQueued = false
      root.saveAttempts += 1
      var why = root.capStr(String(writeErr.text || "").trim(), 120)
      root.saveError = why || (status !== 0 ? "The save helper was stopped" : "Save failed (exit " + code + ")")
      if (root.saveAttempts < root.maxSaveAttempts && !root.dead) {
        saveRetry.interval = 1000 * Math.pow(3, root.saveAttempts - 1)
        saveRetry.restart()
      }
    }
  }
  Timer { id: writeDeadline; interval: 6000; onTriggered: stateWriter.running = false }

  // The helper writes a temp file next to the target, fsyncs it, renames it
  // into place relative to the held directory descriptor, then fsyncs the
  // directory, so a crash mid-write never leaves half a save behind.
  function saveState() {
    if (!stateLoaded || dead) return
    if (stateWriter.running || stateReader.running) { saveQueued = true; return }
    var json = JSON.stringify(root.state)
    if (json.length > maxStateBytes) {
      // Never hand an oversized state to the writer: shed the bulky lists
      // first, and refuse outright if it is somehow still too big.
      var slim = normalize(JSON.parse(json))
      slim.history = slim.history.slice(0, 10)
      slim.pending = slim.pending.slice(0, 5)
      json = JSON.stringify(slim)
      if (json.length > maxStateBytes) { saveError = "The save is too large to write"; return }
    }
    stateWriter.environment = ({ BLAST_STATE: json })
    stateWriter.command = ["/usr/bin/python3", ioHelper, "write"]
    writeDeadline.restart()
    stateWriter.running = true
  }

  Component.onCompleted: loadState()
  Component.onDestruction: root.dead = true
}
