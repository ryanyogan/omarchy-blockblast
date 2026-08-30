import QtQuick

// The three pieces waiting to be placed. The selected one wears a ring;
// pieces that fit nowhere fade so you can see the end coming.
Item {
  id: tray
  required property var ui
  property var pieces: [null, null, null]
  property var fits: [true, true, true]
  property int selected: 0
  property real slotSize: 120
  property real cellSide: 20
  property bool horizontal: false

  implicitWidth: horizontal ? slotSize * 3 + ui.space(10) * 2 : slotSize
  implicitHeight: horizontal ? slotSize : slotSize * 3 + ui.space(10) * 2
  width: implicitWidth
  height: implicitHeight

  // Slide the whole tray up when a fresh set arrives.
  function arrive() {
    if (!ui.animated) return
    for (var i = 0; i < 3; i++) { var s = slots.itemAt(i); if (s) s.arrive(i * 70) }
  }
  function shake(i) {
    var s = slots.itemAt(i)
    if (s) s.shake()
  }

  Grid {
    columns: tray.horizontal ? 3 : 1
    spacing: tray.ui.space(10)
    Repeater {
      id: slots
      model: 3
      delegate: Item {
        id: slot
        required property int index
        readonly property var piece: tray.pieces[index]
        readonly property bool active: index === tray.selected && !!piece
        readonly property bool fitsSomewhere: tray.fits[index] !== false
        width: tray.slotSize
        height: tray.slotSize

        function arrive(delay) { arrivePause.duration = delay; arriveAnim.restart() }
        function shake() { shakeAnim.restart() }

        SequentialAnimation {
          id: arriveAnim
          PropertyAction { target: body; property: "opacity"; value: 0 }
          PropertyAction { target: body; property: "y"; value: 26 }
          PropertyAction { target: body; property: "scale"; value: 0.7 }
          PauseAnimation { id: arrivePause; duration: 0 }
          ParallelAnimation {
            NumberAnimation { target: body; property: "opacity"; to: 1; duration: 200 }
            NumberAnimation { target: body; property: "y"; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            NumberAnimation { target: body; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
          }
        }
        SequentialAnimation {
          id: shakeAnim
          NumberAnimation { target: body; property: "x"; to: -6; duration: 40 }
          NumberAnimation { target: body; property: "x"; to: 6; duration: 70 }
          NumberAnimation { target: body; property: "x"; to: -3; duration: 60 }
          NumberAnimation { target: body; property: "x"; to: 0; duration: 50 }
        }

        Rectangle {
          anchors.fill: parent
          radius: tray.ui.space(12)
          color: slot.active ? tray.ui.trayActive : tray.ui.tray
          border.width: slot.active ? 2 : 1
          border.color: slot.active ? tray.ui.accent : tray.ui.hairline
          Behavior on color { ColorAnimation { duration: 140 } }
          Behavior on border.color { ColorAnimation { duration: 140 } }
        }

        // Slot number, the key that selects it.
        Text {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.margins: tray.ui.space(8)
          text: String(slot.index + 1)
          font.family: tray.ui.font
          font.pixelSize: tray.ui.fontSmall
          font.weight: Font.Bold
          color: slot.active ? tray.ui.accent : tray.ui.dim
        }

        Item {
          id: body
          anchors.fill: parent
          opacity: slot.piece ? (slot.fitsSomewhere ? 1 : 0.28) : 0
          Behavior on opacity { NumberAnimation { duration: 220 } }
          // The selected piece bobs, gently, so the eye finds it. Ambient:
          // stops flat when input goes quiet or the tray is hidden.
          SequentialAnimation on y {
            running: slot.active && tray.ui.ambient && tray.visible
            loops: Animation.Infinite
            onRunningChanged: if (!running) body.y = 0
            NumberAnimation { to: -3; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 800; easing.type: Easing.InOutSine }
          }
          PieceView {
            anchors.centerIn: parent
            ui: tray.ui
            piece: slot.piece
            cellSide: slot.piece ? Math.min(tray.cellSide, (tray.slotSize - tray.ui.space(28)) / Math.max(slot.piece.rows, slot.piece.cols) - 2) : tray.cellSide
            gap: 2
            gloss: slot.fitsSomewhere ? 1 : 0.2
          }
        }

        // Empty slot: a faint dot so the space still reads as a slot.
        Rectangle {
          anchors.centerIn: parent
          width: tray.ui.space(6); height: width; radius: width / 2
          color: tray.ui.hairline
          visible: !slot.piece
        }
      }
    }
  }
}
