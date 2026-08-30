import QtQuick
import "../Game.js" as Game

// The 8x8 board. Owns the cells, the ghost, the shard burst on a clear and
// the floating "+30" that rises off a landing.
Item {
  id: board
  required property var ui
  property var cells: []              // 64 ints
  property var ghostPiece: null       // piece under the cursor, or null
  property int ghostRow: 0
  property int ghostCol: 0
  property bool ghostValid: true
  property color ghostColor: ui.accent
  property var ghostBadCells: []      // indices the ghost overlaps when invalid
  property var clearCells: []         // indices that would clear on drop
  property real side: 400
  property bool dimmed: false

  readonly property real gap: Math.max(3, Math.round(side * 0.014))
  readonly property real cellSide: (side - gap * (Game.SIZE - 1)) / Game.SIZE

  width: side
  height: side

  function cellAt(i) { return grid.itemAt(i) }
  function centerOf(i) {
    var r = Math.floor(i / Game.SIZE), c = i % Game.SIZE
    return { x: c * (cellSide + gap) + cellSide / 2, y: r * (cellSide + gap) + cellSide / 2 }
  }

  // Landing: pop each cell in order, 18 ms apart.
  function landed(indices) {
    for (var i = 0; i < indices.length; i++) { var c = cellAt(indices[i]); if (c) c.pop(i * 18) }
  }

  // Clearing: burst each cell, timed by distance from the piece so the line
  // sweeps away from where the block hit.
  function blast(indices, colors, originIndex) {
    var o = centerOf(originIndex)
    var maxD = 1
    var ds = []
    for (var i = 0; i < indices.length; i++) {
      var p = centerOf(indices[i])
      var d = Math.sqrt((p.x - o.x) * (p.x - o.x) + (p.y - o.y) * (p.y - o.y))
      ds.push(d); if (d > maxD) maxD = d
    }
    for (var j = 0; j < indices.length; j++) {
      var cell = cellAt(indices[j])
      var delay = Math.round(ds[j] / maxD * 160)
      if (cell) cell.blast(colors[indices[j]] || 1, delay)
      if (ui.animated) shards(centerOf(indices[j]), colors[indices[j]] || 1, delay, j % 2 === 0 ? 3 : 2)
    }
  }

  // Shards fly off a cleared cell. Each one is a tiny rotated rectangle
  // with its own arc, created for the flight and destroyed after it.
  Component {
    id: shardComp
    Rectangle {
      id: shard
      property real dx: 0
      property real dy: 0
      property int delay: 0
      width: Math.max(3, board.cellSide * 0.22)
      height: width
      radius: 2
      opacity: 0
      SequentialAnimation {
        running: true
        PauseAnimation { duration: shard.delay }
        PropertyAction { target: shard; property: "opacity"; value: 1 }
        ParallelAnimation {
          NumberAnimation { target: shard; property: "x"; to: shard.x + shard.dx; duration: 520; easing.type: Easing.OutCubic }
          SequentialAnimation {
            NumberAnimation { target: shard; property: "y"; to: shard.y + shard.dy - board.cellSide * 0.6; duration: 220; easing.type: Easing.OutQuad }
            NumberAnimation { target: shard; property: "y"; to: shard.y + shard.dy + board.cellSide * 1.2; duration: 320; easing.type: Easing.InQuad }
          }
          NumberAnimation { target: shard; property: "rotation"; to: shard.dx > 0 ? 260 : -260; duration: 540 }
          NumberAnimation { target: shard; property: "scale"; to: 0.3; duration: 540; easing.type: Easing.InQuad }
          SequentialAnimation {
            PauseAnimation { duration: 300 }
            NumberAnimation { target: shard; property: "opacity"; to: 0; duration: 240 }
          }
        }
        ScriptAction { script: shard.destroy() }
      }
    }
  }

  function shards(center, colorIndex, delay, count) {
    var color = ui.blocks[(colorIndex - 1) % ui.blocks.length]
    for (var i = 0; i < count; i++) {
      var angle = Math.random() * Math.PI * 2
      var dist = cellSide * (0.9 + Math.random() * 1.6)
      shardComp.createObject(board, {
        x: center.x - cellSide * 0.11, y: center.y - cellSide * 0.11, color: color,
        dx: Math.cos(angle) * dist, dy: Math.sin(angle) * dist * 0.6, delay: delay + 40, z: 20
      })
    }
  }

  // Points float up from where the piece landed.
  Component {
    id: floatComp
    Text {
      id: f
      property int delay: 0
      font.family: board.ui.font
      font.pixelSize: board.ui.fontDisplay
      font.weight: Font.Black
      style: Text.Outline
      styleColor: board.ui.light ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(0, 0, 0, 0.6)
      opacity: 0
      scale: 0.6
      SequentialAnimation {
        running: true
        PauseAnimation { duration: f.delay }
        ParallelAnimation {
          NumberAnimation { target: f; property: "opacity"; to: 1; duration: 120 }
          NumberAnimation { target: f; property: "scale"; to: 1.15; duration: 220; easing.type: Easing.OutBack }
          NumberAnimation { target: f; property: "y"; to: f.y - board.cellSide * 1.6; duration: 900; easing.type: Easing.OutCubic }
          SequentialAnimation {
            PauseAnimation { duration: 500 }
            NumberAnimation { target: f; property: "opacity"; to: 0; duration: 380 }
          }
        }
        ScriptAction { script: f.destroy() }
      }
    }
  }

  function floatPoints(index, text, color, delay) {
    if (!ui.animated) return
    var c = centerOf(index)
    var t = floatComp.createObject(board, { text: text, color: color, delay: delay | 0, z: 30 })
    t.x = Math.max(0, Math.min(board.width - t.implicitWidth, c.x - t.implicitWidth / 2))
    // It rises 1.6 cells; keep the whole flight inside the board.
    t.y = Math.max(board.cellSide * 1.6, c.y - t.implicitHeight / 2)
  }

  // Everything below the shards.
  Item {
    anchors.fill: parent
    opacity: board.dimmed ? 0.35 : 1
    Behavior on opacity { NumberAnimation { duration: 400 } }

    Grid {
      id: gridLayout
      columns: Game.SIZE
      rows: Game.SIZE
      spacing: board.gap
      Repeater {
        id: grid
        model: Game.SIZE * Game.SIZE
        delegate: Cell {
          required property int index
          ui: board.ui
          side: board.cellSide
          value: board.cells[index] || 0
          blocked: !board.ghostValid && board.ghostBadCells.indexOf(index) !== -1
          willClear: board.ghostValid && board.clearCells.indexOf(index) !== -1
        }
      }
    }

    // The ghost: one item that glides to the cursor instead of 64 cells
    // flipping on and off, so moving feels like sliding a piece.
    Item {
      id: ghost
      visible: !!board.ghostPiece
      x: board.ghostCol * (board.cellSide + board.gap)
      y: board.ghostRow * (board.cellSide + board.gap)
      width: board.ghostPiece ? board.ghostPiece.cols * (board.cellSide + board.gap) - board.gap : 0
      height: board.ghostPiece ? board.ghostPiece.rows * (board.cellSide + board.gap) - board.gap : 0
      Behavior on x { enabled: board.ui.animated; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
      Behavior on y { enabled: board.ui.animated; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
      z: 5

      // A soft breath so the ghost reads as "not placed yet".
      opacity: 1
      SequentialAnimation on opacity {
        running: ghost.visible && board.ui.animated
        loops: Animation.Infinite
        NumberAnimation { to: 0.72; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
      }

      Repeater {
        model: board.ghostPiece ? board.ghostPiece.cells.length : 0
        delegate: Rectangle {
          required property int index
          readonly property var cell: board.ghostPiece.cells[index]
          x: cell[1] * (board.cellSide + board.gap) + Math.max(1, board.cellSide * 0.06)
          y: cell[0] * (board.cellSide + board.gap) + Math.max(1, board.cellSide * 0.06)
          width: board.cellSide - Math.max(1, board.cellSide * 0.06) * 2
          height: width
          radius: Math.max(3, board.cellSide * 0.18)
          color: board.ghostValid ? Qt.rgba(board.ghostColor.r, board.ghostColor.g, board.ghostColor.b, 0.42) : board.ui.ghostBadFill
          border.width: 2
          border.color: board.ghostValid ? board.ghostColor : board.ui.urgent
          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on border.color { ColorAnimation { duration: 120 } }
        }
      }
    }
  }
}
