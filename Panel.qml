import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Game.js" as Game
import "Palette.js" as Palette

// The dropdown: the world's best runs at a glance and a big Play button.
// One face, one rhythm: header, period pills, eight rows, your line, play.
// Enter starts a game, h/l switch the period, r refreshes, esc closes.
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
  readonly property color dim: Util.alpha(ink, 0.55)
  readonly property color faint: Util.alpha(ink, 0.35)
  readonly property color hairline: Util.alpha(ink, 0.12)
  readonly property color fill: Util.alpha(ink, 0.05)
  readonly property color onAccent: Palette.ink(Color.accent)
  readonly property string fontFamily: Style.font.family

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
  readonly property bool hasSave: service && service.savedGame && !service.savedGame.over && (service.savedGame.moves | 0) > 0

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

  readonly property real panelWidth: Style.space(330)
  readonly property real rowH: Style.space(30)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(column.implicitHeight + Style.space(48), Style.space(700))

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
        anchors.margins: Style.space(14)
        spacing: Style.space(10)

        // Header: logo, name, best.
        Item {
          width: parent.width
          height: Style.space(24)
          Row {
            spacing: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            Grid {
              columns: 2; spacing: 2
              anchors.verticalCenter: parent.verticalCenter
              Repeater {
                model: 4
                delegate: Rectangle {
                  required property int index
                  width: Style.space(7); height: Style.space(7); radius: 2
                  color: root.blocks[[0, 2, 4, 1][index] % root.blocks.length]
                }
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "BLAST"
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.weight: Font.Black
              font.letterSpacing: 3
              color: root.ink
            }
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.best > 0 ? "best " + Game.fmt(root.best) : ""
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: root.dim
          }
        }

        Rectangle { width: parent.width; height: 1; color: root.hairline }

        // Period pills.
        Row {
          spacing: Style.space(6)
          visible: root.lbOn
          Repeater {
            model: 3
            delegate: Rectangle {
              required property int index
              readonly property bool on: root.periods[index] === root.period
              height: Style.space(24)
              width: pt.implicitWidth + Style.space(18)
              radius: height / 2
              color: on ? root.accent : root.fill
              Behavior on color { ColorAnimation { duration: 140 } }
              Text {
                id: pt
                anchors.centerIn: parent
                text: root.periodLabels[index]
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.weight: parent.on ? Font.Bold : Font.Medium
                color: parent.on ? root.onAccent : root.dim
              }
              MouseArea { anchors.fill: parent; onClicked: { root.period = root.periods[index]; root.refresh() } }
            }
          }
        }

        // The board.
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
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.dim
          }
          Text {
            anchors.centerIn: parent
            visible: root.lbOn && root.loading && !root.entries.length
            text: "fetching…"
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.dim
          }
          Text {
            anchors.centerIn: parent
            visible: root.lbOn && !root.loading && !!root.error
            text: root.error + "  ·  r to retry"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: Color.urgent
          }
          Text {
            anchors.centerIn: parent
            visible: root.lbOn && !root.loading && !root.error && !root.entries.length
            text: "No runs yet. Yours could be first."
            font.family: root.fontFamily
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
                  radius: Style.space(6)
                  color: row.mine ? Util.alpha(root.accent, 0.14) : "transparent"
                }
                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(20); height: width; radius: width / 2
                  color: row.index === 0 ? root.blocks[2] : row.index === 1 ? root.blocks[4] : row.index === 2 ? root.blocks[1] : "transparent"
                  Text {
                    anchors.centerIn: parent
                    text: String((row.e.rank | 0) || row.index + 1)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.weight: Font.Bold
                    color: row.index < 3 ? "#111111" : root.dim
                  }
                }
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(34)
                  anchors.right: score.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(row.e.tag || "")
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.weight: row.mine ? Font.Bold : Font.Normal
                  color: row.mine ? root.accent : root.ink
                }
                Text {
                  id: score
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: Game.fmt(row.e.score || 0)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.weight: Font.Bold
                  color: root.ink
                }
              }
            }
          }
        }

        // Your standing.
        Text {
          width: parent.width
          visible: root.lbOn
          elide: Text.ElideRight
          text: root.myTag
            ? "You are @" + root.myTag + (root.myRank ? "  ·  #" + root.myRank + " of " + root.players : "")
            : "Claim a tag in the game to post runs"
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          color: root.myTag ? root.ink : root.dim
        }

        Rectangle { width: parent.width; height: 1; color: root.hairline }

        // Play.
        Rectangle {
          width: parent.width
          height: Style.space(34)
          radius: Style.space(9)
          color: playArea.containsMouse ? Util.alpha(root.accent, 0.85) : root.accent
          Behavior on color { ColorAnimation { duration: 120 } }
          Text {
            anchors.centerIn: parent
            text: root.hasSave ? "Resume game" : "Start a game"
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.Bold
            color: root.onAccent
          }
          MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.play() }
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "enter play   ·   h l period   ·   r refresh   ·   esc close"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.faint
        }
      }
    }
  }
}
