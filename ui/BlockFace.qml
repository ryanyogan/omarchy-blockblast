import QtQuick

// One block, holographic: a translucent pane of its own colour behind a
// luminous edge, flat as projected glass. `gloss` is intensity — a dull
// block (a piece that fits nowhere) fades pane and edge together.
Item {
  id: face
  property color color: "#888888"
  property real side: 40
  property real radius: Math.max(3, side * 0.2)
  property real gloss: 1.0
  width: side
  height: side

  // The pane and its edge.
  Rectangle {
    anchors.fill: parent
    radius: face.radius
    color: Qt.rgba(face.color.r, face.color.g, face.color.b, 0.14 + 0.16 * face.gloss)
    border.width: Math.max(1, Math.round(face.side * 0.05))
    border.color: Qt.rgba(face.color.r, face.color.g, face.color.b, 0.45 + 0.50 * face.gloss)
  }

  // A hairline inner rim for the projected-glass depth. Skipped on blocks
  // too small to carry it.
  Rectangle {
    visible: face.side >= 22
    anchors.fill: parent
    anchors.margins: Math.max(2, face.side * 0.12)
    radius: Math.max(2, face.radius * 0.55)
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(face.color.r, face.color.g, face.color.b, 0.30 * face.gloss)
  }
}
