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
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null

  // ---------------------------------------------------------------- state

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/blast"
  readonly property string stateFilePath: stateDir + "/blast.json"
  readonly property int maxStateBytes: 262144

  // The API this build talks to. Overridable with BLAST_API in the shell's
  // environment or `:api URL` inside the game (saved to the state file).
  readonly property string builtinApi: "https://blast-leaderboard.ryanyogan.workers.dev"
  readonly property string apiBase: {
    var saved = String(state.apiBase || "").replace(/\/+$/, "")
    if (saved) return saved
    var env = String(Quickshell.env("BLAST_API") || "").replace(/\/+$/, "")
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

  function normalize(raw) {
    var s = defaultState()
    if (!raw || typeof raw !== "object") return s
    if (raw.game && typeof raw.game === "object") s.game = raw.game
    if (raw.best && typeof raw.best === "object") {
      s.best = { score: Math.max(0, raw.best.score | 0), lines: Math.max(0, raw.best.lines | 0),
                 maxCombo: Math.max(0, raw.best.maxCombo | 0), at: Number(raw.best.at) || 0 }
    }
    if (Array.isArray(raw.history)) s.history = raw.history.filter(function(h) { return h && typeof h === "object" }).slice(0, 50)
    if (raw.player && typeof raw.player === "object" && typeof raw.player.token === "string" && Game.validTag(raw.player.tag))
      s.player = { id: String(raw.player.id || ""), tag: String(raw.player.tag), token: String(raw.player.token) }
    if (Array.isArray(raw.pending)) s.pending = raw.pending.filter(function(p) { return p && typeof p === "object" }).slice(0, 50)
    if (typeof raw.apiBase === "string") s.apiBase = raw.apiBase
    s.reducedMotion = raw.reducedMotion === true
    s.leaderboardEnabled = raw.leaderboardEnabled !== false
    s.seenIntro = raw.seenIntro === true
    var so = Number(raw.scrimOpacity)
    s.scrimOpacity = isFinite(so) && so > 0 ? Math.max(0.2, Math.min(1, so)) : 0
    s.gamesPlayed = Math.max(0, raw.gamesPlayed | 0)
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

  function saveGame(serialized) { update(function(s) { s.game = serialized }) }
  function clearGame() { update(function(s) { s.game = null }) }
  function setReducedMotion(on) { update(function(s) { s.reducedMotion = on === true }) }
  function setLeaderboardEnabled(on) { update(function(s) { s.leaderboardEnabled = on === true; if (!s.leaderboardEnabled) s.pending = [] }) }
  function markIntroSeen() { update(function(s) { s.seenIntro = true }) }
  function setScrimOpacity(v) { update(function(s) { s.scrimOpacity = v }) }
  function setApiBase(url) { update(function(s) { s.apiBase = String(url || "").trim() }) }

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

  function request(method, path, body, cb) {
    if (!leaderboardEnabled) { cb(null, "Leaderboard is off"); return }
    var xhr = new XMLHttpRequest()
    var url = apiBase + path
    xhr.open(method, url)
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.setRequestHeader("Accept", "application/json")
    xhr.timeout = 8000
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var parsed = null
      try { parsed = xhr.responseText ? JSON.parse(xhr.responseText) : null } catch (e) { parsed = null }
      if (xhr.status === 0) { root.lastError = "No connection"; cb(null, "No connection to " + apiBase); return }
      if (xhr.status >= 200 && xhr.status < 300 && parsed) { root.lastError = ""; cb(parsed, null); return }
      var msg = parsed && parsed.error ? String(parsed.error) : "HTTP " + xhr.status
      root.lastError = msg
      cb(parsed, msg)
    }
    try { xhr.send(body === undefined ? null : JSON.stringify(body)) } catch (e) { cb(null, String(e)) }
  }

  // Claim a gamer tag. On success the token lands in the state file and any
  // pending runs are posted under it.
  function register(tag, cb) {
    tag = String(tag || "").trim()
    if (!Game.validTag(tag)) { cb(null, "2 to 16 letters, numbers, _ or -"); return }
    busy = true
    request("POST", "/v1/players", { tag: tag }, function(res, err) {
      busy = false
      if (err || !res || !res.token) { cb(null, err || "Could not register"); return }
      update(function(s) {
        s.player = { id: String(res.id || ""), tag: String(res.tag), token: String(res.token) }
        // Runs finished before the tag existed are still worth posting.
        var unposted = s.history.filter(function(h) { return !h.posted && h.moves > 0 })
        s.pending = unposted.slice(0, 10)
      })
      cb(res, null)
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
    var lastRes = null, lastErr = null
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
        // A 4xx means the server will never take this one; drop it.
        update(function(s) {
          s.pending = s.pending.filter(function(p) { return p.at !== rec.at })
          for (var i = 0; i < s.history.length; i++) {
            if (s.history[i].at === rec.at) {
              s.history[i].posted = !err
              if (res && res.ok) {
                s.history[i].rank = res.rank | 0
                s.history[i].dayRank = res.dayRank | 0
                s.history[i].personalBest = res.personalBest === true
              }
            }
          }
        })
        if (rec.at === newest.at) {
          if (res && res.ok) { newest.rank = res.rank | 0; newest.dayRank = res.dayRank | 0; newest.personalBest = res.personalBest === true; newest.players = res.players | 0 }
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
      cb(res, err)
    })
  }

  function leaderboard(period, limit, cb) {
    request("GET", "/v1/leaderboard?period=" + encodeURIComponent(period) + "&limit=" + (limit | 0), undefined, cb)
  }

  function profile(tag, cb) {
    request("GET", "/v1/players/" + encodeURIComponent(tag), undefined, cb)
  }

  // ---------------------------------------------------------------- persistence

  property bool dead: false
  property bool saveQueued: false
  Timer { id: saveDebounce; interval: 150; onTriggered: root.saveState() }
  function saveSoon() { if (stateLoaded) saveDebounce.restart() }

  Process {
    id: stateReader
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = null
        try { parsed = text.trim() === "" ? null : JSON.parse(text) } catch (e) { parsed = null }
        root.state = root.normalize(parsed)
        root.stateLoaded = true
      }
    }
  }

  // Re-read the file from disk. The overlay calls this on open so a save
  // edited or synced from elsewhere is what you resume.
  function refresh() {
    if (stateReader.running || stateWriter.running || saveDebounce.running) return
    stateLoaded = false
    loadState()
  }

  function loadState() {
    if (stateReader.running) return
    stateReader.command = ["bash", "-c",
      'f="$0"; [ -e "$f" ] || exit 0; [ -L "$f" ] && exit 1; exec 3<>"$f" || exit 1; '
      + '[ "$(stat -Lc %F /proc/self/fd/3)" = "regular file" ] || exit 1; '
      + 'head -c ' + root.maxStateBytes + ' <&3',
      root.stateFilePath]
    stateReader.running = true
  }

  Process {
    id: stateWriter
    running: false
    onExited: function(code, status) {
      if (root.saveQueued) { root.saveQueued = false; root.saveState() }
    }
  }

  // Temp file beside the target, then an atomic rename, so a crash mid-write
  // never leaves half a save behind.
  function saveState() {
    if (!stateLoaded || dead) return
    if (stateWriter.running || stateReader.running) { saveQueued = true; return }
    stateWriter.command = ["bash", "-c",
      'mkdir -p "$0" || exit 1; tmp=$(mktemp "$0/.blast.XXXXXXXX") && printf \'%s\' "$2" > "$tmp" '
      + '&& mv -f "$tmp" "$1" || { rm -f "$tmp"; exit 1; }',
      root.stateDir, root.stateFilePath, JSON.stringify(root.state)]
    stateWriter.running = true
  }

  Component.onCompleted: loadState()
  Component.onDestruction: root.dead = true
}
