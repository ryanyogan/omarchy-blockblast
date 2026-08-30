import QtQuick

// A piece drawn small, for the tray. Sized to its own bounding box.
Item {
  id: view
  required property var ui
  property var piece: null
  property real cellSide: 18
  property real gap: 2
  property real gloss: 1.0

  implicitWidth: piece ? piece.cols * cellSide + (piece.cols - 1) * gap : cellSide
  implicitHeight: piece ? piece.rows * cellSide + (piece.rows - 1) * gap : cellSide
  width: implicitWidth
  height: implicitHeight

  Repeater {
    model: view.piece ? view.piece.cells.length : 0
    delegate: BlockFace {
      required property int index
      readonly property var cell: view.piece.cells[index]
      x: cell[1] * (view.cellSide + view.gap)
      y: cell[0] * (view.cellSide + view.gap)
      side: view.cellSide
      gloss: view.gloss
      color: view.ui.blocks[(view.piece.color - 1) % view.ui.blocks.length]
    }
  }
}
