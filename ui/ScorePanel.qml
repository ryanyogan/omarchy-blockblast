import QtQuick
import "../Game.js" as Game

// Score, best, lines, combo. The score counts up instead of jumping and the
// combo badge only exists while a streak is alive.
Item {
  id: panel
  required property var ui
  property int score: 0
  property int best: 0
  property int lines: 0
  property int combo: 0
  property string tag: ""
  property bool newBest: false

  implicitHeight: col.implicitHeight
  height: implicitHeight

  property real shown: 0
  Behavior on shown { enabled: panel.ui.animated; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
  onScoreChanged: { shown = score; if (score > 0) bumpAnim.restart() }
  Component.onCompleted: shown = score

  SequentialAnimation {
    id: bumpAnim
    NumberAnimation { target: scoreText; property: "scale"; to: 1.12; duration: 90; easing.type: Easing.OutQuad }
    NumberAnimation { target: scoreText; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutBack }
  }

  Column {
    id: col
    width: parent.width
    spacing: panel.ui.space(2)

    Text {
      text: "SCORE"
      font.family: panel.ui.font
      font.pixelSize: panel.ui.fontSmall
      font.letterSpacing: 2
      color: panel.ui.dim
    }
    Text {
      id: scoreText
      text: Game.fmt(panel.shown)
      font.family: panel.ui.font
      font.pixelSize: panel.ui.fontHero
      font.weight: Font.Black
      color: panel.newBest ? panel.ui.accent : panel.ui.fg
      transformOrigin: Item.Left
      Behavior on color { ColorAnimation { duration: 300 } }
    }

    Item { width: 1; height: panel.ui.space(10) }

    Row {
      spacing: panel.ui.space(24)
      Column {
        spacing: 0
        Text { text: "BEST"; font.family: panel.ui.font; font.pixelSize: panel.ui.fontSmall; font.letterSpacing: 2; color: panel.ui.dim }
        Text { text: Game.fmt(panel.best); font.family: panel.ui.font; font.pixelSize: panel.ui.fontHeading; font.weight: Font.Bold; color: panel.ui.fg }
      }
      Column {
        spacing: 0
        Text { text: "LINES"; font.family: panel.ui.font; font.pixelSize: panel.ui.fontSmall; font.letterSpacing: 2; color: panel.ui.dim }
        Text { text: String(panel.lines); font.family: panel.ui.font; font.pixelSize: panel.ui.fontHeading; font.weight: Font.Bold; color: panel.ui.fg }
      }
    }

    Item { width: 1; height: panel.ui.space(10) }

    // Combo badge.
    Item {
      width: badge.width
      height: panel.ui.space(30)
      Rectangle {
        id: badge
        height: parent.height
        width: badgeText.implicitWidth + panel.ui.space(24)
        radius: height / 2
        color: panel.ui.accent
        opacity: panel.combo > 1 ? 1 : 0
        scale: panel.combo > 1 ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
        Text {
          id: badgeText
          anchors.centerIn: parent
          text: "COMBO  x" + panel.combo
          font.family: panel.ui.font
          font.pixelSize: panel.ui.fontBody
          font.weight: Font.Black
          font.letterSpacing: 1
          color: panel.ui.onAccent
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: panel.tag ? "@" + panel.tag : "no gamer tag  ·  :tag NAME"
        font.family: panel.ui.font
        font.pixelSize: panel.ui.fontSmall
        color: panel.ui.dim
        visible: panel.combo <= 1
      }
    }
  }
}
