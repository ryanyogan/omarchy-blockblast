import QtQuick

// Keys and rules, on one screen.
Item {
  id: help
  required property var ui

  readonly property var keys: [
    ["h j k l", "move the piece"],
    ["0  $", "jump to the left / right edge"],
    ["gg  G", "jump to the top / bottom"],
    ["1 2 3", "pick a piece from the tray"],
    ["w  b   tab", "next / previous piece"],
    ["enter  space", "drop the piece"],
    ["n", "new game"],
    ["t", "leaderboard"],
    ["?", "this screen"],
    [":", "command line"],
    ["esc  q", "back, then quit"]
  ]
  readonly property var commands: [
    [":tag NAME", "claim a gamer tag, or change it"],
    [":new", "start over"],
    [":motion on|off", "animations"],
    [":api URL", "point at another leaderboard"],
    [":logout", "drop the tag on this machine"],
    [":q", "quit"]
  ]

  Column {
    anchors.fill: parent
    spacing: help.ui.space(14)

    Text { text: "HOW TO PLAY"; font.family: help.ui.font; font.pixelSize: help.ui.fontSmall; font.letterSpacing: 3; color: help.ui.dim }
    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Drop pieces anywhere they fit. Fill a row or a column and it clears; there is no gravity. One point per block. A clear pays 10, two at once 30, three 60, four 100, multiplied by your combo: every consecutive clearing move adds one. Empty the board for 300 on top. The game ends when nothing on the tray fits."
      font.family: help.ui.font
      font.pixelSize: help.ui.fontBody
      lineHeight: 1.3
      color: help.ui.fg
    }

    Item { width: 1; height: help.ui.space(2) }
    Text { text: "KEYS"; font.family: help.ui.font; font.pixelSize: help.ui.fontSmall; font.letterSpacing: 3; color: help.ui.dim }
    Grid {
      columns: 2
      columnSpacing: help.ui.space(18)
      rowSpacing: help.ui.space(3)
      Repeater {
        model: help.keys.length * 2
        delegate: Text {
          required property int index
          text: help.keys[Math.floor(index / 2)][index % 2]
          font.family: help.ui.font
          font.pixelSize: help.ui.fontBody
          font.weight: index % 2 === 0 ? Font.Bold : Font.Normal
          color: index % 2 === 0 ? help.ui.accent : help.ui.fg
        }
      }
    }

    Item { width: 1; height: help.ui.space(2) }
    Text { text: "COMMANDS"; font.family: help.ui.font; font.pixelSize: help.ui.fontSmall; font.letterSpacing: 3; color: help.ui.dim }
    Grid {
      columns: 2
      columnSpacing: help.ui.space(18)
      rowSpacing: help.ui.space(3)
      Repeater {
        model: help.commands.length * 2
        delegate: Text {
          required property int index
          text: help.commands[Math.floor(index / 2)][index % 2]
          font.family: help.ui.font
          font.pixelSize: help.ui.fontBody
          font.weight: index % 2 === 0 ? Font.Bold : Font.Normal
          color: index % 2 === 0 ? help.ui.accent : help.ui.fg
        }
      }
    }
  }
}
