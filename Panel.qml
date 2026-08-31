import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Game.js" as Game
import "Palette.js" as Palette

// The dropdown. It looks like the game because it carries the game: a live
// miniature of your saved board next to its score, the world's top eight
// under it, and a Play button built like a block. Enter plays, h/l switch
// the period, r refreshes, esc closes.
Panel {
  id: root
  moduleName: "ryanyogan.blast"
  ipcTarget: "ryanyogan.blast"

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  // ---------------------------------------------------------------- lifecycle

  function open() {
    root.controller.show()
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function openFromHotkey() { open() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function play() {
    close()
    if (root.service) root.service.openOverlay()
  }

  // ---------------------------------------------------------------- theming

  readonly property color ink: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Util.alpha(ink, 0.56)
  readonly property color faint: Util.alpha(ink, 0.34)
  readonly property color hairline: Util.alpha(ink, 0.10)
  readonly property color fill: Util.alpha(ink, 0.05)
  readonly property color well: Util.alpha(ink, 0.07)
  readonly property color onAccent: Palette.ink(Color.accent)
  readonly property string mono: Style.font.family
  readonly property string sans: "Noto Sans"

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
  }
  readonly property var blocks: Palette.blockColors(root.paletteToml, Color.accent)

  // ---------------------------------------------------------------- data

  readonly property bool lbOn: service ? service.leaderboardEnabled !== false : true
  readonly property string myTag: service ? service.tag : ""
  readonly property int best: service ? service.bestScore : 0
  readonly property var save: service && service.savedGame && !service.savedGame.over ? service.savedGame : null
  readonly property bool hasSave: !!(save && (save.moves | 0) > 0)
  readonly property var saveBoard: save && Array.isArray(save.board) ? save.board : []

  property string period: "all"
  readonly property var periods: ["all", "week", "day"]
  readonly property var periodLabels: ["All time", "Week", "Today"]
  property var entries: []
  property int players: 0
  property bool loading: false
  property string error: ""
  property int myRank: 0

  function refresh() {
    if (!service || !lbOn) return
    var wanted = period
    loading = true
    error = ""
    service.leaderboard(wanted, 8, function(res, err) {
      if (root.period !== wanted) return
      root.loading = false
      if (err || !res || !res.ok) { root.error = err || "Could not load"; return }
      root.entries = res.entries || []
      root.players = res.players | 0
    })
    if (service.hasTag) service.verify(function(res, err) {
      if (res && res.ok) root.myRank = res.rank | 0
    })
  }

  function switchPeriod(dir) {
    period = periods[(periods.indexOf(period) + dir + periods.length) % periods.length]
    refresh()
  }

  onOpenedChanged: if (!root.opened) { period = "all" }

  // ---------------------------------------------------------------- frame

  readonly property real panelWidth: Style.space(372)
  readonly property real rowH: Style.space(33)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(column.implicitHeight + Style.space(52), Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onActivateRequested: root.play()
      onReturnRequested: root.play()
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.switchPeriod(dx > 0 ? 1 : -1) }
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root.barIdentity, direction)
      }
      onTextKey: function(t) {
        if (t === "r") root.refresh()
        else if (t === "h") root.switchPeriod(-1)
        else if (t === "l") root.switchPeriod(1)
        else if (t === "q") root.close()
      }

      Column {
        id: column
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.space(16)
        spacing: Style.space(12)

        // ---- header: logo, wordmark, best -------------------------------
        Item {
          width: parent.width
          height: Style.space(26)
          Row {
            spacing: Style.space(9)
            anchors.verticalCenter: parent.verticalCenter
            Grid {
              columns: 2; spacing: 2
              anchors.verticalCenter: parent.verticalCenter
              Repeater {
                model: 4
                delegate: Rectangle {
                  required property int index
                  width: Style.space(8); height: Style.space(8); radius: Style.space(2)
                  color: root.blocks[[0, 2, 4, 1][index] % root.blocks.length]
                  Rectangle {
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1.5 }
                    height: 2; radius: 1
                    color: Qt.rgba(1, 1, 1, 0.35)
                  }
                }
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "BLAST"
              font.family: root.mono
              font.pixelSize: Style.font.title
              font.weight: Font.Black
              font.letterSpacing: 4
              color: root.ink
            }
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(5)
            visible: root.best > 0
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "BEST"
              font.family: root.sans
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1.5
              color: root.faint
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: Game.fmt(root.best)
              font.family: root.mono
              font.pixelSize: Style.font.subtitle
              font.weight: Font.Bold
              color: root.ink
            }
          }
        }

        // ---- the run in your pocket: live mini board + its numbers ------
        Rectangle {
          width: parent.width
          height: mini.height + Style.space(20)
          radius: Style.space(12)
          color: root.fill

          Item {
            id: mini
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            readonly property real cell: Style.spaceReal(11)
            readonly property real gap: Style.spaceReal(1.6)
            width: cell * 8 + gap * 7
            height: width

            Grid {
              columns: 8
              spacing: mini.gap
              Repeater {
                model: 64
                delegate: Rectangle {
                  required property int index
                  readonly property int v: root.saveBoard[index] || 0
                  width: mini.cell; height: mini.cell
                  radius: Math.max(1.5, mini.cell * 0.22)
                  color: v > 0 ? root.blocks[(v - 1) % root.blocks.length] : root.well
                  Rectangle {
                    visible: v > 0
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
                    height: Math.max(1, mini.cell * 0.18)
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.3)
                  }
                }
              }
            }
          }

          Column {
            anchors.left: mini.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Text {
              text: root.hasSave ? "RUN IN PROGRESS" : "FRESH BOARD"
              font.family: root.sans
              font.pixelSize: Style.font.caption
              font.letterSpacing: 2
              color: root.faint
            }
            Text {
              text: root.hasSave ? Game.fmt(root.save.score) : "0"
              font.family: root.mono
              font.pixelSize: Math.round(Style.font.display * 1.15)
              font.weight: Font.Black
              color: root.ink
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: root.hasSave
                ? (root.save.lines | 0) + " lines" + ((root.save.combo | 0) > 1 ? "  ·  combo x" + root.save.combo : "") + "  ·  " + (root.save.moves | 0) + " moves"
                : "64 empty cells waiting"
              font.family: root.sans
              font.pixelSize: Style.font.bodySmall
              color: root.dim
            }
          }
        }

        // ---- period pills + player count --------------------------------
        Item {
          width: parent.width
          height: Style.space(26)
          visible: root.lbOn
          Row {
            spacing: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
              model: 3
              delegate: Rectangle {
                required property int index
                readonly property bool on: root.periods[index] === root.period
                height: Style.space(25)
                width: pt.implicitWidth + Style.space(20)
                radius: height / 2
                color: on ? root.accent : root.fill
                Behavior on color { ColorAnimation { duration: 140 } }
                Text {
                  id: pt
                  anchors.centerIn: parent
                  text: root.periodLabels[index]
                  font.family: root.sans
                  font.pixelSize: Style.font.bodySmall
                  font.weight: parent.on ? Font.DemiBold : Font.Medium
                  color: parent.on ? root.onAccent : root.dim
                }
                MouseArea { anchors.fill: parent; onClicked: { root.period = root.periods[index]; root.refresh() } }
              }
            }
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.players > 0 ? root.players + " players" : ""
            font.family: root.sans
            font.pixelSize: Style.font.caption
            color: root.faint
          }
        }

        // ---- the world --------------------------------------------------
        Item {
          width: parent.width
          height: root.lbOn ? Math.max(root.rowH * 3, rows.implicitHeight) : Style.space(64)

          Text {
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: !root.lbOn
            text: "Leaderboard is off.\nNothing leaves this machine."
            lineHeight: 1.35
            font.family: root.sans
            font.pixelSize: Style.font.body
            color: root.dim
          }
          Text {
            anchors.centerIn: parent
            visible: root.lbOn && root.loading && !root.entries.length
            text: "Fetching the world…"
            font.family: root.sans
            font.pixelSize: Style.font.body
            color: root.dim
          }
          Text {
            anchors.centerIn: parent
            visible: root.lbOn && !root.loading && !!root.error
            text: root.error + "  ·  r to retry"
            font.family: root.sans
            font.pixelSize: Style.font.bodySmall
            color: Color.urgent
          }
          Text {
            anchors.centerIn: parent
            visible: root.lbOn && !root.loading && !root.error && !root.entries.length
            text: "No runs yet. Yours could be first."
            font.family: root.sans
            font.pixelSize: Style.font.body
            color: root.dim
          }

          Column {
            id: rows
            width: parent.width
            opacity: root.loading ? 0.5 : 1
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Repeater {
              model: root.lbOn ? root.entries.length : 0
              delegate: Item {
                id: row
                required property int index
                readonly property var e: root.entries[index] || ({})
                readonly property bool mine: root.myTag && String(e.tag || "").toLowerCase() === root.myTag.toLowerCase()
                width: rows.width
                height: root.rowH

                Rectangle {
                  anchors.fill: parent
                  anchors.topMargin: 1
                  anchors.bottomMargin: 1
                  radius: Style.space(8)
                  color: row.mine ? Util.alpha(root.accent, 0.13) : "transparent"
                }
                // Medal: a block for the podium, a plain number for the rest.
                Rectangle {
                  id: medal
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(21); height: width
                  radius: Style.space(6)
                  color: row.index === 0 ? root.blocks[2] : row.index === 1 ? root.blocks[4] : row.index === 2 ? root.blocks[1] : "transparent"
                  Rectangle {
                    visible: row.index < 3
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 2 }
                    height: 2.5; radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.35)
                  }
                  Text {
                    anchors.centerIn: parent
                    text: String((row.e.rank | 0) || row.index + 1)
                    font.family: root.sans
                    font.pixelSize: Style.font.bodySmall
                    font.weight: Font.Bold
                    color: row.index < 3 ? "#141414" : root.faint
                  }
                }
                Text {
                  anchors.left: medal.right
                  anchors.leftMargin: Style.space(9)
                  anchors.right: meta.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(row.e.tag || "")
                  elide: Text.ElideRight
                  font.family: root.sans
                  font.pixelSize: Style.font.subtitle
                  font.weight: row.mine ? Font.Bold : Font.Medium
                  color: row.mine ? root.accent : root.ink
                }
                Text {
                  id: meta
                  anchors.right: score.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: (row.e.lines | 0) + " ln"
                  font.family: root.sans
                  font.pixelSize: Style.font.caption
                  color: root.faint
                }
                Text {
                  id: score
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: Game.fmt(row.e.score || 0)
                  font.family: root.mono
                  font.pixelSize: Style.font.subtitle
                  font.weight: Font.Bold
                  color: root.ink
                }
              }
            }
          }
        }

        // ---- you --------------------------------------------------------
        Text {
          width: parent.width
          visible: root.lbOn
          elide: Text.ElideRight
          text: root.myTag
            ? "You are @" + root.myTag + (root.myRank ? "  ·  #" + root.myRank + " in the world" : "")
            : "Claim a tag in the game to post runs"
          font.family: root.sans
          font.pixelSize: Style.font.bodySmall
          color: root.myTag ? root.dim : root.faint
        }

        Rectangle { width: parent.width; height: 1; color: root.hairline }

        // ---- play: a button built like a block --------------------------
        Rectangle {
          id: playBtn
          width: parent.width
          height: Style.space(40)
          radius: Style.space(11)
          color: Palette.darken(root.accent, 0.14)

          Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: Math.max(2, parent.height * 0.09)
            radius: parent.radius
            gradient: Gradient {
              GradientStop { position: 0.0; color: playArea.containsMouse ? Palette.lighten(root.accent, 0.14) : Palette.lighten(root.accent, 0.08) }
              GradientStop { position: 1.0; color: root.accent }
            }
          }
          Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            anchors.topMargin: Style.space(4)
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(14)
            height: Style.space(3)
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.28)
          }
          Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: root.hasSave ? "Resume run" : "Start a game"
            font.family: root.sans
            font.pixelSize: Style.font.subtitle
            font.weight: Font.Bold
            color: root.onAccent
          }
          MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.play() }
          scale: playArea.pressed ? 0.98 : 1
          Behavior on scale { NumberAnimation { duration: 80 } }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "enter play   ·   h l period   ·   r refresh   ·   esc"
          font.family: root.sans
          font.pixelSize: Style.font.caption
          color: root.faint
        }
      }
    }
  }
}
