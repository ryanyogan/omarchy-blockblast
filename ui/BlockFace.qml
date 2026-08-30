import QtQuick
import "../Palette.js" as Palette

// One block: a rounded tile with a lit cap and a darker foot, so a wall of
// them reads as candy rather than flat swatches. Cheap: three rectangles.
Item {
  id: face
  property color color: "#888888"
  property real side: 40
  property real radius: Math.max(3, side * 0.2)
  property real gloss: 1.0
  width: side
  height: side

  Rectangle {
    anchors.fill: parent
    radius: face.radius
    color: Palette.darken(face.color, 0.16)
  }
  Rectangle {
    anchors.fill: parent
    anchors.bottomMargin: Math.max(2, face.side * 0.09)
    radius: face.radius
    gradient: Gradient {
      GradientStop { position: 0.0; color: Palette.lighten(face.color, 0.10 * face.gloss) }
      GradientStop { position: 1.0; color: face.color }
    }
  }
  Rectangle {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: Math.max(2, face.side * 0.12)
    anchors.leftMargin: Math.max(3, face.side * 0.16)
    anchors.rightMargin: Math.max(3, face.side * 0.16)
    height: Math.max(2, face.side * 0.12)
    radius: height / 2
    color: Qt.rgba(1, 1, 1, 0.28 * face.gloss)
  }
}
