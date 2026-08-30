import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "Game.js" as Game
import "Palette.js" as Palette
import "ui"

// Blast. The whole game lives on this one full-screen surface: board on the
// left, score and tray on the right, a command line along the bottom.
//
// The shell mounts this only while it is open (kinds: overlay, keepLoaded
// false). Closed, it does not exist; the service keeps the save file.
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  readonly property string pluginId: "ryanyogan.blast"

  // ---------------------------------------------------------------- theme

  // Block colors come from the active theme's colors.toml, so every theme
  // plays in its own palette. The file is re-read whenever the shell's own
  // Color singleton notices a theme swap.
  property string paletteToml: ""
  FileView {
    id: paletteFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.paletteToml = text()
    onLoadFailed: root.paletteToml = ""
  }
  Connections {
    target: Color
    function onAccentChanged() { paletteFile.reload() }
    function onBackgroundChanged() { paletteFile.reload() }
    function onForegroundChanged() { paletteFile.reload() }
  }

  readonly property bool reducedMotion: service ? service.reducedMotion === true : false

  readonly property QtObject ui: QtObject {
    readonly property bool light: Palette.mode(root.paletteToml) === "light"
    readonly property bool animated: root.opened && !root.reducedMotion
    readonly property color fg: Color.foreground
    readonly property color bg: Color.background
    readonly property color accent: Color.accent
    readonly property color urgent: Color.urgent
    readonly property color onAccent: Palette.ink(Color.accent)
    readonly property color dim: Util.alpha(Color.foreground, 0.58)
    readonly property color hairline: Util.alpha(Color.foreground, light ? 0.14 : 0.12)
    readonly property color well: Util.alpha(Color.foreground, light ? 0.07 : 0.06)
    readonly property color wellEdge: Util.alpha(Color.foreground, light ? 0.10 : 0.07)
    readonly property color tray: Util.alpha(Color.foreground, 0.04)
    readonly property color trayActive: Util.alpha(Color.accent, 0.12)
    readonly property color selectedFill: Util.alpha(Color.accent, 0.14)
    readonly property color ghostBadFill: Util.alpha(Color.urgent, 0.22)
    readonly property color card: light ? Palette.lighten(Color.background, 0.03) : Palette.lighten(Color.background, 0.035)
    readonly property color scrim: Util.alpha(Color.background, light ? 0.90 : 0.86)
    readonly property var blocks: Palette.blockColors(root.paletteToml, Color.accent)
    readonly property color stripe: Util.alpha(Color.foreground, 0.03)
    readonly property string font: Style.font.family
    // Prose and lists read better in a proportional face. Falls back to
    // whatever "sans-serif" resolves to if Noto Sans is not installed.
    readonly property string sans: "Noto Sans"
    // Spacing tokens. Everything lays out on these four.
    readonly property int pad: Style.space(32)
    readonly property int gutter: Style.space(24)
    readonly property int section: Style.space(16)
    readonly property int row: Style.space(8)
    readonly property int fontSmall: Style.font.bodySmall
    readonly property int fontBody: Style.font.body
    readonly property int fontSubtitle: Style.font.subtitle
    readonly property int fontHeading: Style.font.heading
    readonly property int fontDisplay: Style.font.display
    readonly property int fontHero: Math.round(Style.font.display * 1.9)
    function space(px) { return Style.space(px) }
  }

  // ---------------------------------------------------------------- game

  property var game: null
  property var cells: []
  property int cursorRow: 3
  property int cursorCol: 3
  property int slot: 0
  property bool busy: false
  property string pane: ""            // "" | board | help | over | tag
  property bool cmdMode: false
  property string toast: ""
  property bool toastError: false
  property bool confirmNew: false
  property bool pendingG: false
  property var overRec: null
  property bool posting: false
  property string postError: ""
  property int scoreShown: 0
  property int comboShown: 0
  property bool newBest: false
  property string tagReturnPane: ""

  readonly property bool playing: !!game && !game.over
  readonly property var piece: game && slot >= 0 && slot < 3 ? game.tray[slot] : null
  readonly property var ghostCells: piece ? Game.cellsOf(piece, cursorRow, cursorCol) : []
  readonly property var ghostBadCells: {
    if (!piece || ghostValid) return []
    var out = []
    for (var i = 0; i < ghostCells.length; i++) if (game.board[ghostCells[i]]) out.push(ghostCells[i])
    return out
  }
  readonly property bool ghostValid: piece ? Game.canPlace(game.board, piece, cursorRow, cursorCol) : true
  readonly property color ghostColor: piece ? ui.blocks[(piece.color - 1) % ui.blocks.length] : ui.accent
  readonly property var clearCells: {
    if (!piece || !ghostValid || pane === "over") return []
    var lines = Game.fullLines(game.board, ghostCells)
    var out = []
    for (var r = 0; r < lines.rows.length; r++) for (var c = 0; c < Game.SIZE; c++) out.push(Game.idx(lines.rows[r], c))
    for (var cc = 0; cc < lines.cols.length; cc++) for (var rr = 0; rr < Game.SIZE; rr++) out.push(Game.idx(rr, lines.cols[cc]))
    return out
  }
  readonly property var trayFits: game ? game.tray.map(function(p) { return !p || !!Game.anyPlacement(game.board, p) }) : [true, true, true]
  readonly property int bestScore: {
    var saved = service ? service.bestScore : 0
    return game && game.score > saved ? game.score : saved
  }
  readonly property string tag: service ? service.tag : ""
  readonly property bool leaderboardOn: service ? service.leaderboardEnabled !== false : true

  function startGame(resume) {
    var saved = resume && service ? service.savedGame : null
    var g = saved ? Game.normalizeState(saved) : null
    if (!g || g.over) g = Game.newGame()
    game = g
    cells = g.board.slice()
    slot = firstSlot(g)
    cursorRow = 3; cursorCol = 3
    clampCursor()
    pane = ""
    overRec = null
    newBest = false
    scoreShown = g.score
    comboShown = g.combo
    if (service) service.saveGame(Game.serialize(g))
    if (!saved || saved.moves === 0) tray.arrive()
    if (g.over) finish()
    else if (service && !service.seenIntro) { pane = "intro"; intro.reveal() }
  }

  function dismissIntro() {
    if (service) service.markIntroSeen()
    pane = basePane()
    showToast("hjkl to move, enter to drop. ? for help", false)
  }

  // Game.place mutates in place; hand QML a fresh object so bindings on
  // game.tray, game.board and friends re-evaluate.
  function bump() {
    var g = Object.assign({}, game)
    g.tray = game.tray.slice()
    game = g
  }

  function firstSlot(g) {
    for (var i = 0; i < 3; i++) if (g.tray[i]) return i
    return 0
  }

  function clampCursor() {
    var a = Game.clampAnchor(piece, cursorRow, cursorCol)
    cursorRow = a.row; cursorCol = a.col
  }

  function move(dr, dc) {
    if (!playing || pane) return
    var a = Game.clampAnchor(piece, cursorRow + dr, cursorCol + dc)
    if (a.row === cursorRow && a.col === cursorCol) return
    cursorRow = a.row; cursorCol = a.col
  }

  function jump(row, col) {
    if (!playing || pane) return
    var a = Game.clampAnchor(piece, row === null ? cursorRow : row, col === null ? cursorCol : col)
    cursorRow = a.row; cursorCol = a.col
  }

  function selectSlot(i) {
    if (!playing || pane) return
    if (!game.tray[i]) { showToast("Slot " + (i + 1) + " is empty", true); return }
    slot = i
    clampCursor()
  }

  function cycleSlot(dir) {
    if (!playing || pane) return
    for (var k = 1; k <= 3; k++) {
      var i = (slot + dir * k + 6) % 3
      if (game.tray[i]) { slot = i; clampCursor(); return }
    }
  }

  // The move. Everything visual hangs off the result Game.place returns.
  function drop() {
    if (!playing || pane || busy) return
    if (!piece) { cycleSlot(1); return }
    if (!ghostValid) {
      tray.shake(slot)
      wobble.restart()
      return
    }
    var origin = Game.idx(cursorRow + piece.cells[0][0], cursorCol + piece.cells[0][1])
    var res = Game.place(game, slot, cursorRow, cursorCol)
    if (!res) return
    busy = true
    bump()

    // Show the piece landed, with the cleared lines still standing.
    var view = game.board.slice()
    for (var i = 0; i < res.cleared.length; i++) view[res.cleared[i]] = res.clearedColors[res.cleared[i]]
    cells = view
    board.landed(res.landed)

    var landedCenter = res.landed[Math.floor(res.landed.length / 2)]
    var settle = 90
    if (res.lineCount > 0) {
      later(140, function() {
        board.blast(res.cleared, res.clearedColors, origin)
        cells = game.board.slice()
        scoreShown = game.score
        comboShown = game.combo
        board.floatPoints(landedCenter, "+" + (res.clearPoints + res.placePoints), res.combo > 1 ? ui.accent : ui.fg, 60)
        if (res.combo > 1) comboPop.restart()
        if (res.allClear) {
          // After the combo pop has had its moment.
          later(res.combo > 1 ? 700 : 150, function() {
            allClearBanner.fire()
            board.floatPoints(27, "+" + res.bonus, ui.accent, 200)
          })
        }
      })
      settle = 520
    } else {
      cells = game.board.slice()
      scoreShown = game.score
      comboShown = game.combo
      board.floatPoints(landedCenter, "+" + res.placePoints, ui.dim, 0)
    }

    if (game.score > (service ? service.bestScore : 0) && (service ? service.bestScore : 0) > 0 && !newBest) {
      newBest = true
      showToast("New best", false)
    }

    if (service) service.saveGame(Game.serialize(game))

    later(settle, function() {
      if (res.refilled) tray.arrive()
      if (!game.tray[slot]) slot = firstSlot(game)
      clampCursor()
      busy = false
      if (res.over) later(res.lineCount ? 200 : 350, finish)
    })
  }

  function finish() {
    if (!game) return
    game.over = true
    bump()
    pane = "over"
    posting = !!(service && service.hasTag && leaderboardOn)
    postError = ""
    overRec = service ? service.finishGame(game, function(rec, err) {
      if (rec) overRec = rec
      posting = false
      postError = err || ""
      if (rec && rec.personalBest && rec.rank) showToast("#" + rec.rank + " in the world", false)
    }) : { score: game.score, lines: game.lines, maxCombo: game.maxCombo, moves: game.moves, localBest: false }
    gameOver.reveal()
  }

  function newGame() {
    if (playing && game.moves > 0 && !confirmNew) {
      confirmNew = true
      showToast("Press n again to abandon this run", false)
      confirmTimer.restart()
      return
    }
    confirmNew = false
    if (playing && game.moves > 0 && service) service.clearGame()
    startGame(false)
    showToast("New game", false)
  }
  Timer { id: confirmTimer; interval: 2200; onTriggered: root.confirmNew = false }

  // ---------------------------------------------------------------- panes

  function openBoard() {
    pane = "board"
    if (!leaderboardOn) return
    fetchBoard()
    if (service && service.hasTag) service.verify(function(res, err) {
      if (res && res.ok) { leaderboard.myRank = res.rank | 0; leaderboard.myBest = res.best | 0 }
    })
  }

  function fetchBoard() {
    if (!service) return
    leaderboard.loading = true
    leaderboard.error = ""
    var period = leaderboard.period
    service.leaderboard(period, 100, function(res, err) {
      if (leaderboard.period !== period) return
      leaderboard.loading = false
      if (err || !res || !res.ok) { leaderboard.error = err || "Could not load"; return }
      leaderboard.entries = res.entries || []
      leaderboard.players = res.players | 0
      leaderboard.games = res.games | 0
    })
  }

  function openTag(returnTo) {
    if (!leaderboardOn) { showToast("Leaderboard is off. :leaderboard on to post runs", true); return }
    tagReturnPane = returnTo || ""
    tagPrompt.reset(tag)
    tagPrompt.busy = false
    pane = "tag"
    Qt.callLater(function() { tagPrompt.takeFocus() })
  }

  function register(text) {
    if (!service) return
    tagPrompt.busy = true
    tagPrompt.error = ""
    service.register(text, function(res, err) {
      tagPrompt.busy = false
      if (err) { tagPrompt.error = err; return }
      showToast("@" + res.tag + " is yours", false)
      pane = tagReturnPane
      content.forceActiveFocus()
      if (pane === "over") {
        posting = true
        service.flushPending(function(rec, e) {
          if (rec) overRec = rec
          posting = false
          postError = e || ""
        })
      } else if (pane === "board") openBoard()
      else service.flushPending(null)
    })
  }

  // Where "back" lands: the game, or the game-over card if the run is done.
  function basePane() { return game && game.over ? "over" : "" }

  function closePane() {
    if (pane === "over") return false
    if (pane === "tag") { pane = tagReturnPane || basePane(); content.forceActiveFocus(); if (pane === "board") openBoard(); return true }
    if (pane) { pane = basePane(); return true }
    return false
  }

  // ---------------------------------------------------------------- commands

  function runCommand(line) {
    var parts = String(line || "").trim().replace(/^:/, "").split(/\s+/)
    var cmd = (parts[0] || "").toLowerCase()
    var arg = parts.slice(1).join(" ")
    switch (cmd) {
    case "": return
    case "q": case "quit": case "exit": close(); return
    case "new": case "restart": confirmNew = true; newGame(); return
    case "tag": case "name": case "register":
      if (arg) register(arg); else openTag(basePane())
      return
    case "logout": case "forget":
      if (service) service.forget()
      showToast("Tag forgotten on this machine", false); return
    case "leaderboard": case "board-on": case "online":
      if (service) service.setLeaderboardEnabled(!(arg === "off" || arg === "0" || arg === "false" || arg === "no"))
      showToast(root.leaderboardOn ? "Leaderboard on" : "Leaderboard off. Nothing leaves this machine", false)
      if (pane === "board") openBoard()
      return
    case "motion":
      if (service) service.setReducedMotion(arg === "off" || arg === "0" || arg === "false")
      showToast("Motion " + (root.reducedMotion ? "off" : "on"), false); return
    case "api":
      if (service) service.setApiBase(arg)
      showToast(arg ? "API: " + arg : "API reset to default", false); return
    case "help": case "h": case "keys": pane = "help"; return
    case "board": case "top": case "lb": case "scores": openBoard(); return
    case "resume": case "play": pane = basePane(); return
    default: showToast("Unknown command: " + cmd, true); return
    }
  }

  function showToast(text, isError) {
    toast = text
    toastError = isError === true
    toastTimer.restart()
  }
  Timer { id: toastTimer; interval: 2000; onTriggered: root.toast = "" }

  // ---------------------------------------------------------------- keys

  function handleKey(event) {
    var k = event.key
    var t = event.text
    var shift = event.modifiers & Qt.ShiftModifier

    if (pane === "tag" || cmdMode) return     // those inputs own the keyboard
    if (pane === "intro") {
      if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || k === Qt.Key_Escape || t === "q") dismissIntro()
      else if (t === "?") { dismissIntro(); pane = "help" }
      event.accepted = true; return
    }

    // Global.
    if (k === Qt.Key_Escape) {
      if (pane === "over") { close(); event.accepted = true; return }
      if (!closePane()) close()
      event.accepted = true; return
    }
    if (t === ":") { cmdMode = true; cmd.text = ""; Qt.callLater(function() { cmd.forceActiveFocus() }); event.accepted = true; return }
    if (t === "?") { pane = pane === "help" ? basePane() : "help"; event.accepted = true; return }
    if (t === "t") { if (pane === "board") pane = basePane(); else openBoard(); event.accepted = true; return }
    if (t === "n") { if (pane !== "board" && pane !== "help") newGame(); event.accepted = true; return }
    if (t === "q") { close(); event.accepted = true; return }

    if (pane === "board") {
      if (t === "h") leaderboard.prev(), fetchBoard()
      else if (t === "l") leaderboard.next(), fetchBoard()
      else if (t === "j") leaderboard.down()
      else if (t === "k") leaderboard.up()
      else if (t === "G") leaderboard.bottom()
      else if (t === "r") fetchBoard()
      else if (t === "g") { if (pendingG) { leaderboard.top(); pendingG = false } else { pendingG = true; gTimer.restart() } }
      event.accepted = true; return
    }
    if (pane === "help") {
      if (t === "j") helpPane.down()
      else if (t === "k") helpPane.up()
      else if (t === "G") helpPane.bottom()
      else if (t === "g") { if (pendingG) { helpPane.top(); pendingG = false } else { pendingG = true; gTimer.restart() } }
      event.accepted = true; return
    }
    if (pane === "over") {
      if (t === "r") openTag("over")
      event.accepted = true; return
    }

    // Board.
    if (t === "g") {
      if (pendingG) { jump(0, null); pendingG = false } else { pendingG = true; gTimer.restart() }
      event.accepted = true; return
    }
    pendingG = false
    switch (true) {
    case t === "h" || k === Qt.Key_Left: move(0, -1); break
    case t === "j" || k === Qt.Key_Down: move(1, 0); break
    case t === "k" || k === Qt.Key_Up: move(-1, 0); break
    case t === "l" || k === Qt.Key_Right: move(0, 1); break
    case t === "H": jump(null, 0); break
    case t === "L": jump(null, Game.SIZE); break
    case t === "K": jump(0, null); break
    case t === "J": jump(Game.SIZE, null); break
    case t === "0" || k === Qt.Key_Home: jump(null, 0); break
    case t === "$" || k === Qt.Key_End: jump(null, Game.SIZE); break
    case t === "G": jump(Game.SIZE, null); break
    case t === "1": selectSlot(0); break
    case t === "2": selectSlot(1); break
    case t === "3": selectSlot(2); break
    case t === "w" || (k === Qt.Key_Tab && !shift): cycleSlot(1); break
    case t === "b" || k === Qt.Key_Backtab || (k === Qt.Key_Tab && shift): cycleSlot(-1); break
    case k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || t === "i": drop(); break
    case t === "r": openTag(basePane()); break
    default: return
    }
    event.accepted = true
  }
  Timer { id: gTimer; interval: 600; onTriggered: root.pendingG = false }

  // ---------------------------------------------------------------- helpers

  Component { id: timerComp; Timer { property var fn: null; repeat: false; running: true; onTriggered: { if (fn) fn(); destroy() } } }
  function later(ms, fn) { timerComp.createObject(root, { interval: Math.max(1, ms | 0), fn: fn }) }

  // Play clock. One tick a second while a run is live and the window is up.
  Timer {
    interval: 1000
    running: root.opened && root.playing && root.pane !== "over"
    repeat: true
    onTriggered: if (root.game) root.game.playedMs = (root.game.playedMs || 0) + 1000
  }

  // ---------------------------------------------------------------- lifecycle

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (String(screens[i].name || "") === name) return screens[i]
    return null
  }

  function open(payloadJson) {
    if (!service && shell && typeof shell.serviceFor === "function") service = shell.serviceFor(pluginId)
    var screen = focusedScreen()
    if (screen) panel.screen = screen
    exit.stop()
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    if (!opened) {
      opened = true
      toast = ""
      cmdMode = false
      if (service) { service.refresh(); waitForState.start() }
      if (ui.animated) enter.restart()
      if (service && service.hasTag) service.flushPending(null)
    }
    if (payload.pane === "board") openBoard()
    if (payload.pane === "help") pane = "help"
    Qt.callLater(function() { if (root.opened) content.forceActiveFocus() })
  }
  Timer {
    id: waitForState
    interval: 40; repeat: true
    onTriggered: if (root.service && root.service.stateLoaded) { stop(); root.startGame(true) }
  }

  function close() {
    if (!opened) return
    if (game && service) service.saveGame(game.over ? null : Game.serialize(game))
    opened = false
    cmdMode = false
    if (ui.animated || exit.running) exit.restart()
    else finishClose()
  }
  function finishClose() {
    if (shell && typeof shell.hide === "function") Qt.callLater(function() { shell.hide(pluginId) })
  }
  function toggle() { opened ? close() : open("{}") }

  // ---------------------------------------------------------------- motion

  ParallelAnimation {
    id: enter
    NumberAnimation { target: scrim; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    SequentialAnimation {
      PauseAnimation { duration: 40 }
      NumberAnimation { target: content; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }
    SpringAnimation { target: content; property: "scale"; from: 0.94; to: 1; spring: 3.2; damping: 0.28; mass: 1; epsilon: 0.005 }
  }
  SequentialAnimation {
    id: exit
    ParallelAnimation {
      NumberAnimation { target: content; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
      NumberAnimation { target: content; property: "scale"; to: 0.98; duration: 140; easing.type: Easing.InCubic }
      NumberAnimation { target: scrim; property: "opacity"; to: 0; duration: 200; easing.type: Easing.OutCubic }
    }
    ScriptAction { script: root.finishClose() }
  }
  SequentialAnimation {
    id: wobble
    NumberAnimation { target: board; property: "anchors.horizontalCenterOffset"; to: -5; duration: 40 }
    NumberAnimation { target: board; property: "anchors.horizontalCenterOffset"; to: 5; duration: 70 }
    NumberAnimation { target: board; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
  }
  SequentialAnimation {
    id: comboPop
    NumberAnimation { target: comboBanner; property: "opacity"; to: 1; duration: 80 }
    NumberAnimation { target: comboBanner; property: "scale"; from: 0.5; to: 1.15; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 3 }
    NumberAnimation { target: comboBanner; property: "scale"; to: 1; duration: 120 }
    PauseAnimation { duration: 500 }
    NumberAnimation { target: comboBanner; property: "opacity"; to: 0; duration: 260 }
  }

  // ---------------------------------------------------------------- window

  PanelWindow {
    id: panel
    visible: root.opened || exit.running
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "blast-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    Rectangle {
      id: scrim
      anchors.fill: parent
      color: root.ui.scrim
      opacity: root.reducedMotion ? 1 : 0
      MouseArea { anchors.fill: parent; enabled: root.opened; onClicked: root.close() }
    }

    Rectangle {
      id: content
      anchors.centerIn: parent
      width: Math.min(panel.width - root.ui.space(64), root.ui.space(1180))
      height: Math.min(panel.height - root.ui.space(64), root.ui.space(790))
      radius: root.ui.space(22)
      color: root.ui.card
      border.width: 1
      border.color: root.ui.hairline
      opacity: root.reducedMotion ? 1 : 0
      scale: root.reducedMotion ? 1 : 0.94
      transformOrigin: Item.Center
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { root.handleKey(event) }
      MouseArea { anchors.fill: parent; onClicked: content.forceActiveFocus() }

      readonly property real pad: root.ui.pad
      readonly property real sideWidth: root.ui.space(360)
      readonly property real boardSide: Math.min(height - pad * 2 - header.height - footer.height - root.ui.space(24), width - pad * 3 - sideWidth)

      // Header: wordmark and the tag.
      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: content.pad
        anchors.bottomMargin: 0
        height: root.ui.space(30)

        Row {
          spacing: root.ui.space(10)
          anchors.verticalCenter: parent.verticalCenter
          Grid {
            columns: 3; spacing: 2
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
              model: 9
              delegate: BlockFace {
                required property int index
                side: root.ui.space(7)
                radius: 2
                color: root.ui.blocks[index % root.ui.blocks.length]
              }
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "BLAST"
            font.family: root.ui.font
            font.pixelSize: root.ui.fontHeading
            font.weight: Font.Black
            font.letterSpacing: 4
            color: root.ui.fg
          }
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: (root.tag && root.leaderboardOn ? "@" + root.tag + "   ·   " : "") + (root.leaderboardOn ? "t leaderboard   ·   " : "offline   ·   ") + "? help"
          font.family: root.ui.font
          font.pixelSize: root.ui.fontSmall
          color: root.ui.dim
        }
      }

      // The board.
      Item {
        id: boardArea
        anchors.left: parent.left
        anchors.leftMargin: content.pad
        anchors.top: header.bottom
        anchors.bottom: footer.top
        width: content.boardSide

        Board {
          id: board
          ui: root.ui
          anchors.centerIn: parent
          side: content.boardSide
          cells: root.cells
          ghostPiece: root.pane ? null : root.piece
          ghostRow: root.cursorRow
          ghostCol: root.cursorCol
          ghostValid: root.ghostValid
          ghostColor: root.ghostColor
          ghostBadCells: root.pane ? [] : root.ghostBadCells
          clearCells: root.clearCells
          dimmed: root.pane === "over" || root.pane === "tag" || root.pane === "intro"
        }

        // Backdrop for the cards that sit over the board.
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + root.ui.space(16)
          height: Math.min(parent.height, root.pane === "intro" ? root.ui.space(420) : root.ui.space(300))
          radius: root.ui.space(18)
          color: Util.alpha(root.ui.card, 0.95)
          border.width: 1
          border.color: root.ui.hairline
          visible: opacity > 0
          opacity: root.pane === "over" || root.pane === "tag" || root.pane === "intro" ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 200 } }
          Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        // Combo banner bursts over the board.
        Rectangle {
          id: comboBanner
          anchors.centerIn: parent
          width: comboText.implicitWidth + root.ui.space(48)
          height: root.ui.space(64)
          radius: height / 2
          color: root.ui.accent
          opacity: 0
          Text {
            id: comboText
            anchors.centerIn: parent
            text: "COMBO  x" + root.comboShown
            font.family: root.ui.font
            font.pixelSize: root.ui.fontDisplay
            font.weight: Font.Black
            font.letterSpacing: 2
            color: root.ui.onAccent
          }
        }

        // Board clear banner.
        Item {
          id: allClearBanner
          anchors.centerIn: parent
          width: parent.width
          height: root.ui.space(90)
          opacity: 0
          function fire() { if (root.ui.animated) allClearAnim.restart() }
          SequentialAnimation {
            id: allClearAnim
            PropertyAction { target: ring; property: "scale"; value: 0.2 }
            PropertyAction { target: ring; property: "opacity"; value: 1 }
            ParallelAnimation {
              NumberAnimation { target: allClearBanner; property: "opacity"; to: 1; duration: 120 }
              NumberAnimation { target: ring; property: "scale"; to: 2.6; duration: 700; easing.type: Easing.OutCubic }
              NumberAnimation { target: ring; property: "opacity"; to: 0; duration: 700 }
            }
            PauseAnimation { duration: 700 }
            NumberAnimation { target: allClearBanner; property: "opacity"; to: 0; duration: 300 }
          }
          Rectangle {
            id: ring
            anchors.centerIn: parent
            width: root.ui.space(160); height: width; radius: width / 2
            color: "transparent"
            border.width: root.ui.space(6)
            border.color: root.ui.accent
            opacity: 0
          }
          Text {
            anchors.centerIn: parent
            text: "BOARD CLEAR"
            font.family: root.ui.font
            font.pixelSize: root.ui.fontHero
            font.weight: Font.Black
            font.letterSpacing: 6
            color: root.ui.accent
            style: Text.Outline
            styleColor: root.ui.card
          }
        }

        GameOverCard {
          id: gameOver
          ui: root.ui
          anchors.fill: parent
          visible: opacity > 0
          opacity: root.pane === "over" ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 180 } }
          rec: root.overRec
          posting: root.posting
          postError: root.postError
          hasTag: !!root.tag
          leaderboardOn: root.leaderboardOn
          best: root.bestScore
        }

        IntroCard {
          id: intro
          ui: root.ui
          anchors.fill: parent
          visible: opacity > 0
          opacity: root.pane === "intro" ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        TagPrompt {
          id: tagPrompt
          ui: root.ui
          anchors.fill: parent
          anchors.margins: root.ui.space(24)
          visible: root.pane === "tag"
          currentTag: root.tag
          onSubmitted: function(text) { root.register(text) }
          onCancelled: root.closePane()
        }
      }

      // Right column: score and tray, or a pane.
      Item {
        id: side
        anchors.right: parent.right
        anchors.rightMargin: content.pad
        anchors.top: header.bottom
        anchors.topMargin: root.ui.section
        anchors.bottom: footer.top
        anchors.bottomMargin: root.ui.section
        width: content.sideWidth

        Column {
          anchors.fill: parent
          spacing: root.ui.gutter
          visible: opacity > 0
          opacity: root.pane !== "board" && root.pane !== "help" ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 160 } }

          ScorePanel {
            id: scorePanel
            ui: root.ui
            width: parent.width
            score: root.scoreShown
            best: root.bestScore
            lines: root.game ? root.game.lines : 0
            combo: root.comboShown
            tag: root.tag
            newBest: root.newBest
          }

          Column {
            spacing: root.ui.row
            Text { text: "TRAY"; font.family: root.ui.font; font.pixelSize: root.ui.fontSmall; font.letterSpacing: 2; color: root.ui.dim }
            Row {
              spacing: root.ui.row
              Tray {
                id: tray
                ui: root.ui
                pieces: root.game ? root.game.tray : [null, null, null]
                fits: root.trayFits
                selected: root.slot
                horizontal: true
                slotSize: Math.min(root.ui.space(100), (side.width - root.ui.space(20)) / 3)
                cellSide: root.ui.space(16)
              }
            }
          }

          RecentRuns {
            ui: root.ui
            width: parent.width
            runs: root.service && root.service.state ? root.service.state.history : []
          }
        }

        Leaderboard {
          id: leaderboard
          ui: root.ui
          anchors.fill: parent
          visible: opacity > 0
          opacity: root.pane === "board" ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 160 } }
          myTag: root.tag
          enabled: root.leaderboardOn
        }
        HelpPane {
          id: helpPane
          ui: root.ui
          anchors.fill: parent
          visible: opacity > 0
          opacity: root.pane === "help" ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 160 } }
          leaderboardOn: root.leaderboardOn
          motionOn: !root.reducedMotion
          tag: root.tag
        }
      }

      // Footer: hints, toast, command line.
      Item {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: content.pad
        anchors.topMargin: 0
        height: root.ui.space(30)

        Rectangle {
          anchors.fill: parent
          radius: root.ui.space(8)
          color: root.cmdMode ? root.ui.well : "transparent"
          border.width: root.cmdMode ? 1 : 0
          border.color: root.ui.accent
        }
        Text {
          anchors.left: parent.left
          anchors.leftMargin: root.ui.space(10)
          anchors.verticalCenter: parent.verticalCenter
          visible: root.cmdMode
          text: ":"
          font.family: root.ui.font
          font.pixelSize: root.ui.fontBody
          font.weight: Font.Bold
          color: root.ui.accent
        }
        TextInput {
          id: cmd
          anchors.fill: parent
          anchors.leftMargin: root.ui.space(22)
          anchors.rightMargin: root.ui.space(10)
          verticalAlignment: TextInput.AlignVCenter
          visible: root.cmdMode
          font.family: root.ui.font
          font.pixelSize: root.ui.fontBody
          color: root.ui.fg
          selectionColor: root.ui.accent
          selectedTextColor: root.ui.onAccent
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.cmdMode = false; content.forceActiveFocus(); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              var line = cmd.text
              root.cmdMode = false
              content.forceActiveFocus()
              root.runCommand(line)
              event.accepted = true
            }
          }
        }
        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.cmdMode
          elide: Text.ElideRight
          text: root.toast ? root.toast
            : root.pane === "over" ? "n new game   ·   t leaderboard   ·   r gamer tag   ·   : command   ·   q quit"
            : root.pane === "tag" ? "enter claim   ·   esc skip"
            : root.pane === "board" ? "h l switch period   ·   j k scroll   ·   r refresh   ·   esc back"
            : root.pane === "help" ? "j k scroll   ·   gg G top / bottom   ·   esc back"
            : root.pane === "intro" ? "enter to play   ·   ? for help"
            : "hjkl move   ·   1 2 3 pick   ·   w b cycle   ·   enter drop   ·   n new   ·   : command"
          font.family: root.ui.font
          font.pixelSize: root.ui.fontSmall
          font.weight: root.toast ? Font.Bold : Font.Normal
          color: root.toastError ? root.ui.urgent : root.toast ? root.ui.accent : root.ui.dim
        }
      }
    }
  }
}
