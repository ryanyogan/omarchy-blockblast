import QtQuick

// First launch. The four things you need, then out of the way.
Item {
  id: intro
  required property var ui

  function reveal() { if (ui.animated) revealAnim.restart() }
  SequentialAnimation {
    id: revealAnim
    PropertyAction { target: col; property: "opacity"; value: 0 }
    PropertyAction { target: col; property: "y"; value: 16 }
    ParallelAnimation {
      NumberAnimation { target: col; property: "opacity"; to: 1; duration: 260 }
      NumberAnimation { target: col; property: "y"; to: 0; duration: 320; easing.type: Easing.OutCubic }
    }
  }

  Column {
    id: col
    anchors.centerIn: parent
    width: parent.width - intro.ui.gutter * 2
    spacing: intro.ui.section

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "WELCOME TO BLAST"
      font.family: intro.ui.font
      font.pixelSize: intro.ui.fontSmall
      font.letterSpacing: 4
      color: intro.ui.dim
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      lineHeight: 1.35
      text: "Fill rows or columns to clear them. Keep going until nothing fits. It plays with vim motions, so the keys you learn here are the keys you use everywhere."
      font.family: intro.ui.sans
      font.pixelSize: intro.ui.fontSubtitle
      color: intro.ui.fg
    }

    Grid {
      anchors.horizontalCenter: parent.horizontalCenter
      columns: 2
      columnSpacing: intro.ui.gutter
      rowSpacing: intro.ui.space(6)
      Text { text: "h j k l"; font.family: intro.ui.font; font.pixelSize: intro.ui.fontSubtitle; font.weight: Font.Bold; color: intro.ui.accent }
      Text { text: "move the piece"; font.family: intro.ui.sans; font.pixelSize: intro.ui.fontSubtitle; color: intro.ui.fg }
      Text { text: "1 2 3"; font.family: intro.ui.font; font.pixelSize: intro.ui.fontSubtitle; font.weight: Font.Bold; color: intro.ui.accent }
      Text { text: "pick a piece"; font.family: intro.ui.sans; font.pixelSize: intro.ui.fontSubtitle; color: intro.ui.fg }
      Text { text: "enter"; font.family: intro.ui.font; font.pixelSize: intro.ui.fontSubtitle; font.weight: Font.Bold; color: intro.ui.accent }
      Text { text: "drop it"; font.family: intro.ui.sans; font.pixelSize: intro.ui.fontSubtitle; color: intro.ui.fg }
      Text { text: "?"; font.family: intro.ui.font; font.pixelSize: intro.ui.fontSubtitle; font.weight: Font.Bold; color: intro.ui.accent }
      Text { text: "everything else, any time"; font.family: intro.ui.sans; font.pixelSize: intro.ui.fontSubtitle; color: intro.ui.fg }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: "Nothing is logged. The leaderboard is optional and only ever sees a gamer tag and a score."
      font.family: intro.ui.sans
      font.pixelSize: intro.ui.fontBody
      color: intro.ui.dim
    }
    Text {
      id: pressEnter
      anchors.horizontalCenter: parent.horizontalCenter
      text: "press enter to play"
      font.family: intro.ui.font
      font.pixelSize: intro.ui.fontBody
      font.weight: Font.Bold
      color: intro.ui.accent
      SequentialAnimation on opacity {
        running: intro.visible && intro.ui.ambient
        loops: Animation.Infinite
        onRunningChanged: if (!running) pressEnter.opacity = 1
        NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
      }
    }
  }
}
