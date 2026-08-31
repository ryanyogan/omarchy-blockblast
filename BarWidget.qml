import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Game.js" as Game
import "Palette.js" as Palette

// Blast in the bar: a tiny four-block cluster in the theme's own colors.
// Left click drops the leaderboard panel down, right click launches the game.
BarWidget {
  id: root
  moduleName: "ryanyogan.blast"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(root.moduleName) : null
  readonly property color ink: bar ? bar.barForeground : Color.foreground
  readonly property bool showBest: setting("showBest", false) === true
  readonly property int best: service ? service.bestScore : 0

  // Block colors follow the theme, same as the game board.
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

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  function togglePanel() { if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle() }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey() }
  function close() { if (panelLoader.item && panelLoader.item.close) panelLoader.item.close() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Math.round(content.implicitWidth + Style.spaceReal(8.5) * 2)
    tooltipText: root.best > 0 ? "Blast · best " + Game.fmt(root.best) : "Blast · block puzzle, vim keys"

    onPressed: function(b) {
      if (b === Qt.RightButton || b === Qt.MiddleButton) { if (root.service) root.service.openOverlay() }
      else root.togglePanel()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      // Four blocks, two by two.
      Grid {
        anchors.verticalCenter: parent.verticalCenter
        columns: 2
        spacing: Math.max(1, Math.round(Style.bar.iconCanvas * 0.12))
        Repeater {
          model: 4
          delegate: Rectangle {
            required property int index
            readonly property real side: (Style.bar.iconCanvas - Math.max(1, Math.round(Style.bar.iconCanvas * 0.12))) / 2
            width: side
            height: side
            radius: Math.max(1.5, side * 0.28)
            color: root.blocks[[0, 2, 4, 1][index] % root.blocks.length]
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showBest && root.best > 0
        text: Game.fmt(root.best)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        color: root.ink
      }
    }
  }
}
