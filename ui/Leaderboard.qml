import QtQuick
import "../Game.js" as Game

// The global board. Three periods, your own row lit, j/k to scroll.
Item {
  id: lb
  required property var ui
  property string period: "all"
  property var entries: []
  property int players: 0
  property int games: 0
  property bool loading: false
  property string error: ""
  property string myTag: ""
  property int scroll: 0
  property int myRank: 0
  property int myBest: 0

  readonly property var periods: ["all", "week", "day"]
  readonly property var periodLabels: ["ALL TIME", "THIS WEEK", "TODAY"]
  readonly property int rowH: ui.space(30)
  readonly property int visibleRows: Math.max(4, Math.floor((height - header.height - footer.height - ui.space(32)) / rowH))

  function next() { period = periods[(periods.indexOf(period) + 1) % periods.length]; scroll = 0 }
  function prev() { period = periods[(periods.indexOf(period) + periods.length - 1) % periods.length]; scroll = 0 }
  function down() { scroll = Math.min(Math.max(0, entries.length - visibleRows), scroll + 1) }
  function up() { scroll = Math.max(0, scroll - 1) }
  function top() { scroll = 0 }
  function bottom() { scroll = Math.max(0, entries.length - visibleRows) }

  Column {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: lb.ui.space(10)

    Text {
      text: "LEADERBOARD"
      font.family: lb.ui.font
      font.pixelSize: lb.ui.fontSmall
      font.letterSpacing: 3
      color: lb.ui.dim
    }
    Row {
      spacing: lb.ui.space(8)
      Repeater {
        model: 3
        delegate: Rectangle {
          required property int index
          readonly property bool on: lb.periods[index] === lb.period
          height: lb.ui.space(26)
          width: t.implicitWidth + lb.ui.space(20)
          radius: height / 2
          color: on ? lb.ui.accent : "transparent"
          border.width: 1
          border.color: on ? lb.ui.accent : lb.ui.hairline
          Behavior on color { ColorAnimation { duration: 140 } }
          Text {
            id: t
            anchors.centerIn: parent
            text: lb.periodLabels[index]
            font.family: lb.ui.font
            font.pixelSize: lb.ui.fontSmall
            font.weight: Font.Bold
            font.letterSpacing: 1
            color: parent.on ? lb.ui.onAccent : lb.ui.dim
          }
        }
      }
    }
  }

  Item {
    id: list
    anchors.top: header.bottom
    anchors.topMargin: lb.ui.space(16)
    anchors.bottom: footer.top
    anchors.left: parent.left
    anchors.right: parent.right
    clip: true

    Text {
      anchors.centerIn: parent
      visible: lb.loading && !lb.entries.length
      text: "fetching…"
      font.family: lb.ui.font
      font.pixelSize: lb.ui.fontBody
      color: lb.ui.dim
    }
    Text {
      anchors.centerIn: parent
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      visible: !lb.loading && !!lb.error
      text: lb.error
      font.family: lb.ui.font
      font.pixelSize: lb.ui.fontBody
      color: lb.ui.urgent
    }
    Text {
      anchors.centerIn: parent
      visible: !lb.loading && !lb.error && !lb.entries.length
      text: "No runs yet. Yours could be first."
      font.family: lb.ui.font
      font.pixelSize: lb.ui.fontBody
      color: lb.ui.dim
    }

    Column {
      width: parent.width
      opacity: lb.loading ? 0.5 : 1
      Behavior on opacity { NumberAnimation { duration: 150 } }
      Repeater {
        model: Math.max(0, Math.min(lb.visibleRows, lb.entries.length - lb.scroll))
        delegate: Item {
          id: row
          required property int index
          readonly property var e: lb.entries[lb.scroll + index] || ({})
          readonly property bool mine: lb.myTag && String(e.tag || "").toLowerCase() === lb.myTag.toLowerCase()
          width: parent.width
          height: lb.rowH

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -lb.ui.space(8)
            anchors.rightMargin: -lb.ui.space(8)
            radius: lb.ui.space(6)
            color: row.mine ? lb.ui.selectedFill : "transparent"
          }
          Text {
            id: rank
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: lb.ui.space(34)
            text: String(row.e.rank || "")
            font.family: lb.ui.font
            font.pixelSize: lb.ui.fontBody
            font.weight: Font.Bold
            color: row.e.rank === 1 ? lb.ui.blocks[2] : row.e.rank === 2 ? lb.ui.blocks[4] : row.e.rank === 3 ? lb.ui.blocks[1] : lb.ui.dim
          }
          Text {
            anchors.left: rank.right
            anchors.right: meta.left
            anchors.verticalCenter: parent.verticalCenter
            text: String(row.e.tag || "")
            elide: Text.ElideRight
            font.family: lb.ui.font
            font.pixelSize: lb.ui.fontBody
            font.weight: row.mine ? Font.Bold : Font.Normal
            color: row.mine ? lb.ui.accent : lb.ui.fg
          }
          Text {
            id: meta
            anchors.right: score.left
            anchors.rightMargin: lb.ui.space(16)
            anchors.verticalCenter: parent.verticalCenter
            text: (row.e.lines | 0) + " ln  x" + (row.e.maxCombo | 0)
            font.family: lb.ui.font
            font.pixelSize: lb.ui.fontSmall
            color: lb.ui.dim
          }
          Text {
            id: score
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Game.fmt(row.e.score || 0)
            font.family: lb.ui.font
            font.pixelSize: lb.ui.fontBody
            font.weight: Font.Bold
            color: lb.ui.fg
          }
        }
      }
    }
  }

  Column {
    id: footer
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: lb.ui.space(4)
    Rectangle { width: parent.width; height: 1; color: lb.ui.hairline }
    Item { width: 1; height: lb.ui.space(4) }
    Text {
      width: parent.width
      text: lb.myTag
        ? "@" + lb.myTag + (lb.myRank ? "  ·  #" + lb.myRank + " all time  ·  best " + Game.fmt(lb.myBest) : "")
        : "Post your runs: register a tag with  :tag NAME"
      elide: Text.ElideRight
      font.family: lb.ui.font
      font.pixelSize: lb.ui.fontSmall
      color: lb.myTag ? lb.ui.fg : lb.ui.dim
    }
    Text {
      text: lb.players + " players  ·  " + lb.games + " games" + (lb.entries.length > lb.visibleRows ? "  ·  j/k scroll" : "") + "  ·  h/l period  ·  esc back"
      font.family: lb.ui.font
      font.pixelSize: lb.ui.fontSmall
      color: lb.ui.dim
    }
  }
}
