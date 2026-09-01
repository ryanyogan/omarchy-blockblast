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

  // The small-caps status line under the name: your best and where it puts
  // you. PanelHero uppercases it.
  readonly property string heroMeta: {
    var bits = []
    if (root.best > 0) bits.push("Best " + Game.fmt(root.best))
    if (root.lbOn && root.myRank > 0) bits.push("#" + root.myRank + " in the world")
    return bits.length ? bits.join("  ·  ") : "No runs yet"
  }

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
    // Column top margin + column + a gap, then the part of the flush play
    // bar that rises above the padding it bleeds through.
    contentHeight: panel.fittedContentHeight(
      column.implicitHeight + Style.space(16) + playBtn.height - panel.padding, Style.space(760))

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
        anchors.margins: Style.space(2)
        spacing: Style.space(12)

        // ---- header -----------------------------------------------------

        // Same shape as the HEY plugin's header (and Hydrate's, Omaday's,
        // Omatop's): mark, name, a small-caps status line, and an action on
        // the trailing edge.
        Item {
          id: heroItem
          width: parent.width
          height: hero.implicitHeight

          // Inside the Component blocks below, PanelHero's internal
          // `id: root` shadows the panel's; state goes through this handle.
          readonly property var blast: root

          PanelHero {
            id: hero
            width: parent.width
            title: "Blast"
            meta: root.heroMeta
            foreground: root.ink
            fontFamily: root.mono
            iconComponent: Component {
              Grid {
                columns: 2; spacing: 2.5
                Repeater {
                  model: 4
                  delegate: Rectangle {
                    required property int index
                    readonly property color c: heroItem.blast.blocks[[0, 2, 4, 1][index] % heroItem.blast.blocks.length]
                    width: Style.space(11); height: Style.space(11); radius: Style.space(3)
                    color: Qt.rgba(c.r, c.g, c.b, 0.28)
                    border.width: 1
                    border.color: Qt.rgba(c.r, c.g, c.b, 0.95)
                  }
                }
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: heroItem.blast.ink
                fontFamily: heroItem.blast.mono
                onClicked: heroItem.blast.refresh()
              }
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.ink }

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
                  readonly property color c: v > 0 ? root.blocks[(v - 1) % root.blocks.length] : root.well
                  width: mini.cell; height: mini.cell
                  radius: Math.max(1.5, mini.cell * 0.22)
                  color: v > 0 ? Qt.rgba(c.r, c.g, c.b, 0.28) : root.well
                  border.width: v > 0 ? 1 : 0
                  border.color: Qt.rgba(c.r, c.g, c.b, 0.95)
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

        // ---- period tabs + player count ---------------------------------

        // Flat text tabs: the active period wears the accent and a short
        // rule under it. No pills, nothing filled.
        Item {
          width: parent.width
          height: Style.space(24)
          visible: root.lbOn
          Row {
            spacing: Style.space(18)
            anchors.bottom: parent.bottom
            Repeater {
              model: 3
              delegate: Item {
                id: tab
                required property int index
                readonly property bool on: root.periods[index] === root.period
                width: pt.implicitWidth
                height: Style.space(24)
                Text {
                  id: pt
                  anchors.top: parent.top
                  text: root.periodLabels[index]
                  font.family: root.sans
                  font.pixelSize: Style.font.bodySmall
                  font.weight: tab.on ? Font.DemiBold : Font.Medium
                  color: tab.on ? root.accent : tabArea.containsMouse ? root.dim : root.faint
                  Behavior on color { ColorAnimation { duration: 140 } }
                }
                Rectangle {
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: 2
                  radius: 1
                  color: root.accent
                  opacity: tab.on ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 140 } }
                }
                MouseArea {
                  id: tabArea
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: { root.period = root.periods[tab.index]; root.refresh() }
                }
              }
            }
          }
          Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(4)
            text: root.players > 0 ? root.players + " players" : ""
            font.family: root.sans
            font.pixelSize: Style.font.caption
            color: root.faint
          }
        }

        // ---- the world --------------------------------------------------
        Item {
          width: parent.width
          height: root.lbOn ? Math.max(root.rowH * (skeleton.visible ? 5 : 3), rows.implicitHeight) : Style.space(64)

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
          // While the world loads: ghost rows in the shape the real ones
          // will take, breathing gently. No spinner, no text jump.
          Column {
            id: skeleton
            width: parent.width
            visible: root.lbOn && root.loading && !root.entries.length
            onVisibleChanged: opacity = 1

            SequentialAnimation on opacity {
              running: skeleton.visible
              loops: Animation.Infinite
              NumberAnimation { from: 1; to: 0.4; duration: 650; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.4; to: 1; duration: 650; easing.type: Easing.InOutSine }
            }

            Repeater {
              model: 5
              delegate: Item {
                id: ghost
                required property int index
                width: skeleton.width
                height: root.rowH
                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(21); height: width
                  radius: Style.space(6)
                  color: root.fill
                }
                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(36)
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width * [0.42, 0.30, 0.48, 0.26, 0.36][ghost.index]
                  height: Style.space(10)
                  radius: Style.space(5)
                  color: root.fill
                }
                Rectangle {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(44)
                  height: Style.space(10)
                  radius: Style.space(5)
                  color: root.fill
                }
              }
            }
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
                  readonly property color c: row.index === 0 ? root.blocks[2] : row.index === 1 ? root.blocks[4] : root.blocks[1]
                  readonly property bool podium: row.index < 3
                  width: Style.space(21); height: width
                  radius: Style.space(6)
                  color: podium ? Qt.rgba(c.r, c.g, c.b, 0.22) : "transparent"
                  border.width: podium ? 1 : 0
                  border.color: Qt.rgba(c.r, c.g, c.b, 0.95)
                  Text {
                    anchors.centerIn: parent
                    text: String((row.e.rank | 0) || row.index + 1)
                    font.family: root.sans
                    font.pixelSize: Style.font.bodySmall
                    font.weight: Font.Bold
                    color: medal.podium ? root.ink : root.faint
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
          text: root.myTag ? "You are @" + root.myTag : "Claim a tag in the game to post runs"
          font.family: root.sans
          font.pixelSize: Style.font.bodySmall
          color: root.myTag ? root.dim : root.faint
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "h l period   ·   r refresh   ·   esc"
          font.family: root.sans
          font.pixelSize: Style.font.caption
          color: root.faint
        }
      }

      // ---- play: a flat bar flush with the card -------------------------

      // The whole bottom of the card is the button: edge to edge, in line
      // with the border, no chrome. It bleeds through the panel's padding
      // and takes the card's own bottom corners.
      Rectangle {
        id: playBtn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: -panel.padding
        anchors.rightMargin: -panel.padding
        anchors.bottomMargin: -panel.padding
        height: Style.space(44)
        radius: 0
        bottomLeftRadius: Math.max(0, Style.cornerRadius - Style.space(2))
        bottomRightRadius: Math.max(0, Style.cornerRadius - Style.space(2))
        color: playArea.pressed ? Palette.darken(root.accent, 0.10)
             : playArea.containsMouse ? Palette.lighten(root.accent, 0.07)
             : root.accent
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
          anchors.centerIn: parent
          text: (root.hasSave ? "Resume run" : "Start a game") + "   ↵"
          font.family: root.sans
          font.pixelSize: Style.font.subtitle
          font.weight: Font.Bold
          color: root.onAccent
        }
        MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.play() }
      }
    }
  }
}
