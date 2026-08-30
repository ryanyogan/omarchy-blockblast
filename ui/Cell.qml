import QtQuick

// One square of the board. Shows a block when `value` is set, a ghost of the
// piece under the cursor, a pulse on lines about to clear, and it owns its
// own landing pop and clearing burst so the board only has to say when.
Item {
  id: cell
  required property var ui
  property int value: 0
  property real side: 40
  property bool blocked: false        // a filled cell the ghost would overlap
  property bool willClear: false
  readonly property bool filled: value > 0

  width: side
  height: side

  // Empty well.
  Rectangle {
    anchors.fill: parent
    radius: Math.max(3, cell.side * 0.2)
    color: cell.ui.well
    border.width: 1
    border.color: cell.ui.wellEdge
  }

  // The block.
  BlockFace {
    id: block
    anchors.centerIn: parent
    side: cell.side
    color: cell.filled ? cell.ui.blocks[(cell.value - 1) % cell.ui.blocks.length] : "transparent"
    visible: cell.filled
    transformOrigin: Item.Center
  }

  // Line-about-to-clear pulse: a bright veil that breathes while there is
  // input, and holds steady once the hands are still.
  Rectangle {
    id: veil
    anchors.fill: parent
    radius: Math.max(3, cell.side * 0.2)
    color: cell.ui.light ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.34)
    visible: cell.willClear && cell.filled
    opacity: cell.willClear ? 0.85 : 0
    SequentialAnimation on opacity {
      running: cell.willClear && cell.ui.ambient
      loops: Animation.Infinite
      onRunningChanged: if (!running) veil.opacity = cell.willClear ? 0.85 : 0
      NumberAnimation { to: 0.25; duration: 420; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.85; duration: 420; easing.type: Easing.InOutSine }
    }
  }

  // The block the ghost is bumping into.
  Rectangle {
    anchors.fill: parent
    radius: Math.max(3, cell.side * 0.2)
    color: cell.ui.ghostBadFill
    visible: cell.blocked && cell.filled
  }

  // Settle glow: a ring that blooms and fades right after a landing.
  Rectangle {
    id: glow
    anchors.centerIn: parent
    width: cell.side; height: cell.side
    radius: Math.max(3, cell.side * 0.2)
    color: "transparent"
    border.width: 2
    border.color: "white"
    opacity: 0
    scale: 1
  }

  // Burst used when this cell clears. Keeps its own color copy since the
  // board value goes to zero the moment the line clears.
  Rectangle {
    id: flash
    anchors.fill: parent
    radius: Math.max(3, cell.side * 0.2)
    color: "white"
    opacity: 0
  }
  BlockFace {
    id: burst
    anchors.centerIn: parent
    side: cell.side
    visible: false
    transformOrigin: Item.Center
  }

  function pop(delay) {
    if (!cell.ui.animated) return
    popAnim.stop()
    popPause.duration = Math.max(0, delay | 0)
    popAnim.start()
  }
  SequentialAnimation {
    id: popAnim
    PauseAnimation { id: popPause; duration: 0 }
    PropertyAction { target: block; property: "scale"; value: 0.4 }
    PropertyAction { target: block; property: "opacity"; value: 0.6 }
    ParallelAnimation {
      NumberAnimation { target: block; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
      NumberAnimation { target: block; property: "opacity"; to: 1.0; duration: 120 }
      SequentialAnimation {
        PropertyAction { target: glow; property: "scale"; value: 0.9 }
        PropertyAction { target: glow; property: "opacity"; value: 0.7 }
        ParallelAnimation {
          NumberAnimation { target: glow; property: "scale"; to: 1.45; duration: 380; easing.type: Easing.OutCubic }
          NumberAnimation { target: glow; property: "opacity"; to: 0; duration: 380 }
        }
      }
    }
  }

  function blast(colorIndex, delay) {
    if (!cell.ui.animated) return
    blastAnim.stop()
    burst.color = cell.ui.blocks[(Math.max(1, colorIndex) - 1) % cell.ui.blocks.length]
    blastPause.duration = Math.max(0, delay | 0)
    blastAnim.start()
  }
  SequentialAnimation {
    id: blastAnim
    PauseAnimation { id: blastPause; duration: 0 }
    PropertyAction { target: burst; property: "visible"; value: true }
    PropertyAction { target: burst; property: "scale"; value: 1 }
    PropertyAction { target: burst; property: "opacity"; value: 1 }
    ParallelAnimation {
      SequentialAnimation {
        NumberAnimation { target: flash; property: "opacity"; to: 0.9; duration: 70 }
        NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 220 }
      }
      SequentialAnimation {
        NumberAnimation { target: burst; property: "scale"; to: 1.18; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: burst; property: "scale"; to: 0; duration: 220; easing.type: Easing.InBack }
      }
      SequentialAnimation {
        PauseAnimation { duration: 120 }
        NumberAnimation { target: burst; property: "opacity"; to: 0; duration: 190 }
      }
    }
    PropertyAction { target: burst; property: "visible"; value: false }
  }
}
