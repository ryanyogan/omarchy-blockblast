import QtQuick

// Rules, keys, why the keys are what they are, what leaves your machine,
// and the settings. j/k scroll it.
Item {
  id: help
  required property var ui
  property bool leaderboardOn: true
  property bool motionOn: true
  property string tag: ""
  property int scrimPct: 86
  property int scroll: 0

  readonly property int step: ui.space(60)
  readonly property int maxScroll: Math.max(0, body.implicitHeight - height)
  function down() { scroll = Math.min(maxScroll, scroll + step) }
  function up() { scroll = Math.max(0, scroll - step) }
  function top() { scroll = 0 }
  function bottom() { scroll = maxScroll }

  readonly property var keys: [
    ["h  j  k  l", "move the piece left, down, up, right"],
    ["0  $", "jump to the left or right edge"],
    ["gg  G", "jump to the top or bottom"],
    ["1  2  3", "pick a piece from the tray"],
    ["w  b   tab", "next or previous piece"],
    ["enter  space", "drop the piece"],
    ["n", "new game"],
    ["t", "leaderboard"],
    ["r", "claim or change your gamer tag"],
    ["?", "this screen"],
    [":", "command line"],
    ["esc  q", "back, then quit"]
  ]
  readonly property var commands: [
    [":tag NAME", "claim a gamer tag, or change it"],
    [":leaderboard on|off", "post runs and show the board, or never touch the network"],
    [":motion on|off", "animations"],
    [":opacity 20-100", "background dimming behind the game (:opacity default resets)"],
    [":logout", "forget the tag on this machine"],
    [":api URL", "point at a different leaderboard server"],
    [":save", "write the save file now (a failed save retries on its own)"],
    [":new", "start over"],
    [":q", "quit"]
  ]

  clip: true

  Column {
    id: body
    width: parent.width
    y: -help.scroll
    spacing: help.ui.section
    Behavior on y { enabled: help.ui.animated; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    Text { text: "HOW TO PLAY"; font.family: help.ui.font; font.pixelSize: help.ui.fontSmall; font.letterSpacing: 3; color: help.ui.dim }
    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      lineHeight: 1.35
      text: "Drop pieces anywhere they fit. Fill a row or a column and it clears; there is no gravity. One point per block. A clear pays 10, two at once 30, three 60, four 100, multiplied by your combo: every consecutive clearing move adds one. Empty the board for 300 on top. The game ends when nothing on the tray fits."
      font.family: help.ui.sans
      font.pixelSize: help.ui.fontBody
      color: help.ui.fg
    }

    Text { text: "WHY THESE KEYS"; font.family: help.ui.font; font.pixelSize: help.ui.fontSmall; font.letterSpacing: 3; color: help.ui.dim }
    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      lineHeight: 1.35
      text: "Part of the point of Blast is to make vim motions land without effort. Every move on the board is a vim motion: hjkl to walk, 0 and $ for the ends of a line, gg and G for the top and bottom, w and b to hop between pieces. Play for a while and the keys stop being something you think about, in the game and in your editor."
      font.family: help.ui.sans
      font.pixelSize: help.ui.fontBody
      color: help.ui.fg
    }

    Text { text: "KEYS"; font.family: help.ui.font; font.pixelSize: help.ui.fontSmall; font.letterSpacing: 3; color: help.ui.dim }
    Grid {
      columns: 2
      columnSpacing: help.ui.gutter
      rowSpacing: help.ui.space(5)
      Repeater {
        model: help.keys.length * 2
        delegate: Text {
          required property int index
          text: help.keys[Math.floor(index / 2)][index % 2]
          font.family: index % 2 === 0 ? help.ui.font : help.ui.sans
          font.pixelSize: help.ui.fontBody
          font.weight: index % 2 === 0 ? Font.Bold : Font.Normal
          color: index % 2 === 0 ? help.ui.accent : help.ui.fg
        }
      }
    }

    Text { text: "COMMANDS"; font.family: help.ui.font; font.pixelSize: help.ui.fontSmall; font.letterSpacing: 3; color: help.ui.dim }
    Grid {
      columns: 2
      columnSpacing: help.ui.gutter
      rowSpacing: help.ui.space(5)
      Repeater {
        model: help.commands.length * 2
        delegate: Text {
          required property int index
          text: help.commands[Math.floor(index / 2)][index % 2]
          font.family: index % 2 === 0 ? help.ui.font : help.ui.sans
          font.pixelSize: help.ui.fontBody
          font.weight: index % 2 === 0 ? Font.Bold : Font.Normal
          color: index % 2 === 0 ? help.ui.accent : help.ui.fg
        }
      }
    }

    Text { text: "SETTINGS"; font.family: help.ui.font; font.pixelSize: help.ui.fontSmall; font.letterSpacing: 3; color: help.ui.dim }
    Grid {
      columns: 2
      columnSpacing: help.ui.gutter
      rowSpacing: help.ui.space(5)
      Text { text: "Leaderboard"; font.family: help.ui.sans; font.pixelSize: help.ui.fontBody; color: help.ui.fg }
      Text { text: help.leaderboardOn ? "on" : "off"; font.family: help.ui.font; font.pixelSize: help.ui.fontBody; font.weight: Font.Bold; color: help.leaderboardOn ? help.ui.accent : help.ui.dim }
      Text { text: "Animations"; font.family: help.ui.sans; font.pixelSize: help.ui.fontBody; color: help.ui.fg }
      Text { text: help.motionOn ? "on" : "off"; font.family: help.ui.font; font.pixelSize: help.ui.fontBody; font.weight: Font.Bold; color: help.motionOn ? help.ui.accent : help.ui.dim }
      Text { text: "Gamer tag"; font.family: help.ui.sans; font.pixelSize: help.ui.fontBody; color: help.ui.fg }
      Text { textFormat: Text.PlainText; text: help.tag ? "@" + help.tag : "none"; font.family: help.ui.font; font.pixelSize: help.ui.fontBody; font.weight: Font.Bold; color: help.tag ? help.ui.accent : help.ui.dim }
      Text { text: "Background opacity"; font.family: help.ui.sans; font.pixelSize: help.ui.fontBody; color: help.ui.fg }
      Text { text: help.scrimPct + "%"; font.family: help.ui.font; font.pixelSize: help.ui.fontBody; font.weight: Font.Bold; color: help.ui.accent }
    }

    Text { text: "PRIVACY"; font.family: help.ui.font; font.pixelSize: help.ui.fontSmall; font.letterSpacing: 3; color: help.ui.dim }
    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      lineHeight: 1.35
      text: "Nothing is logged. The leaderboard server keeps exactly two things: the gamer tag you typed and the scores you post with it. No email, no account, no IP addresses, no analytics, no crash reports. Your tag is tied to a random token that lives in ~/.local/state/blast and is stored on the server only as a hash. :logout forgets it here, and DELETE on the API removes you entirely. With the leaderboard off, Blast never opens a network connection at all."
      font.family: help.ui.sans
      font.pixelSize: help.ui.fontBody
      color: help.ui.fg
    }
    Item { width: 1; height: help.ui.section }
  }
}
