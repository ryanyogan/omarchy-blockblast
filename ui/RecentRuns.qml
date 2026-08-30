import QtQuick
import "../Game.js" as Game

// The last few runs on this machine, newest first.
Item {
  id: recent
  required property var ui
  property var runs: []
  readonly property var shown: (runs || []).slice(0, 6)

  implicitHeight: shown.length ? col.implicitHeight : 0
  height: implicitHeight
  visible: shown.length > 0

  function ago(at) {
    var s = Math.floor((Date.now() - at) / 1000)
    if (s < 60) return "just now"
    if (s < 3600) return Math.floor(s / 60) + "m ago"
    if (s < 86400) return Math.floor(s / 3600) + "h ago"
    return Math.floor(s / 86400) + "d ago"
  }

  Column {
    id: col
    width: parent.width
    spacing: recent.ui.space(4)
    Text { text: "RECENT RUNS"; font.family: recent.ui.font; font.pixelSize: recent.ui.fontSmall; font.letterSpacing: 2; color: recent.ui.dim }
    Item { width: 1; height: recent.ui.space(2) }
    Repeater {
      model: recent.shown.length
      delegate: Item {
        required property int index
        readonly property var r: recent.shown[index]
        width: col.width
        height: recent.ui.space(22)
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: Game.fmt(r.score)
          font.family: recent.ui.font
          font.pixelSize: recent.ui.fontBody
          font.weight: Font.Bold
          color: r.personalBest ? recent.ui.accent : recent.ui.fg
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: (r.lines | 0) + " ln  ·  x" + (r.maxCombo | 0) + (r.rank ? "  ·  #" + r.rank : "") + "  ·  " + recent.ago(r.at)
          font.family: recent.ui.font
          font.pixelSize: recent.ui.fontSmall
          color: recent.ui.dim
        }
      }
    }
  }
}
