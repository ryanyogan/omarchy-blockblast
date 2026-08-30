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
  property bool enabled: true

  readonly property var periods: ["all", "week", "day"]
  readonly property var periodLabels: ["All time", "This week", "Today"]
  readonly property int rowH: ui.space(36)
  readonly property int visibleRows: Math.max(4, Math.floor(list.height / rowH))

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
    spacing: lb.ui.section

    Text {
      text: "LEADERBOARD"
      font.family: lb.ui.font
      font.pixelSize: lb.ui.fontSmall
      font.letterSpacing: 3
      color: lb.ui.dim
    }
    Row {
      spacing: lb.ui.row
      Repeater {
        model: 3
        delegate: Rectangle {
          required property int index
          readonly property bool on: lb.periods[index] === lb.period
          height: lb.ui.space(30)
          width: t.implicitWidth + lb.ui.space(24)
          radius: height / 2
          color: on ? lb.ui.accent : lb.ui.well
          Behavior on color { ColorAnimation { duration: 160 } }
          Text {
            id: t
            anchors.centerIn: parent
            text: lb.periodLabels[index]
            font.family: lb.ui.sans
            font.pixelSize: lb.ui.fontBody
            font.weight: parent.on ? Font.DemiBold : Font.Medium
            color: parent.on ? lb.ui.onAccent : lb.ui.dim
          }
        }
      }
    }
  }

  // Column headings.
  Item {
    id: heads
    anchors.top: header.bottom
    anchors.topMargin: lb.ui.section
    anchors.left: parent.left
    anchors.right: parent.right
    height: lb.ui.space(22)
    visible: lb.entries.length > 0
    Text { anchors.left: parent.left; text: "#"; font.family: lb.ui.sans; font.pixelSize: lb.ui.fontSmall; color: lb.ui.dim }
    Text { anchors.left: parent.left; anchors.leftMargin: lb.ui.space(40); text: "Player"; font.family: lb.ui.sans; font.pixelSize: lb.ui.fontSmall; color: lb.ui.dim }
    Text { anchors.right: parent.right; anchors.rightMargin: lb.ui.space(150); text: "Lines"; font.family: lb.ui.sans; font.pixelSize: lb.ui.fontSmall; color: lb.ui.dim }
    Text { anchors.right: parent.right; anchors.rightMargin: lb.ui.space(96); text: "Combo"; font.family: lb.ui.sans; font.pixelSize: lb.ui.fontSmall; color: lb.ui.dim }
    Text { anchors.right: parent.right; text: "Score"; font.family: lb.ui.sans; font.pixelSize: lb.ui.fontSmall; color: lb.ui.dim }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: lb.ui.hairline }
  }

  Item {
    id: list
    anchors.top: heads.visible ? heads.bottom : header.bottom
    anchors.topMargin: lb.ui.row
    anchors.bottom: footer.top
    anchors.bottomMargin: lb.ui.section
    anchors.left: parent.left
    anchors.right: parent.right
    clip: true

    Text {
      anchors.centerIn: parent
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      visible: !lb.enabled
      text: "The leaderboard is off.\nTurn it on with  :leaderboard on"
      lineHeight: 1.4
      font.family: lb.ui.sans
      font.pixelSize: lb.ui.fontSubtitle
      color: lb.ui.dim
    }
    Text {
      anchors.centerIn: parent
      visible: lb.enabled && lb.loading && !lb.entries.length
      text: "Fetching…"
      font.family: lb.ui.sans
      font.pixelSize: lb.ui.fontSubtitle
      color: lb.ui.dim
    }
    Text {
      anchors.centerIn: parent
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      visible: lb.enabled && !lb.loading && !!lb.error
      text: lb.error + "\nPress  r  to retry."
      lineHeight: 1.4
      font.family: lb.ui.sans
      font.pixelSize: lb.ui.fontBody
      color: lb.ui.urgent
    }
    Text {
      anchors.centerIn: parent
      visible: lb.enabled && !lb.loading && !lb.error && !lb.entries.length
      text: "No runs yet. Yours could be first."
      font.family: lb.ui.sans
      font.pixelSize: lb.ui.fontSubtitle
      color: lb.ui.dim
    }

    Column {
      width: parent.width
      opacity: lb.loading ? 0.5 : 1
      Behavior on opacity { NumberAnimation { duration: 150 } }
      Repeater {
        model: lb.enabled ? Math.max(0, Math.min(lb.visibleRows, lb.entries.length - lb.scroll)) : 0
        delegate: Item {
          id: row
          required property int index
          readonly property var e: lb.entries[lb.scroll + index] || ({})
          readonly property bool mine: lb.myTag && String(e.tag || "").toLowerCase() === lb.myTag.toLowerCase()
          readonly property int place: e.rank | 0
          width: parent.width
          height: lb.rowH

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -lb.ui.row
            anchors.rightMargin: -lb.ui.row
            radius: lb.ui.space(8)
            color: row.mine ? lb.ui.selectedFill : (index % 2 ? lb.ui.stripe : "transparent")
          }
          // Medal for the top three.
          Rectangle {
            id: medal
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: lb.ui.space(26); height: width; radius: width / 2
            color: row.place === 1 ? lb.ui.blocks[2] : row.place === 2 ? lb.ui.blocks[4] : row.place === 3 ? lb.ui.blocks[1] : "transparent"
            Text {
              anchors.centerIn: parent
              text: String(row.place || "")
              font.family: lb.ui.sans
              font.pixelSize: lb.ui.fontBody
              font.weight: Font.DemiBold
              color: row.place <= 3 ? "#111111" : lb.ui.dim
            }
          }
          Text {
            anchors.left: parent.left
            anchors.leftMargin: lb.ui.space(40)
            anchors.right: linesT.left
            anchors.verticalCenter: parent.verticalCenter
            text: String(row.e.tag || "")
            elide: Text.ElideRight
            font.family: lb.ui.sans
            font.pixelSize: lb.ui.fontSubtitle
            font.weight: row.mine ? Font.Bold : Font.Medium
            color: row.mine ? lb.ui.accent : lb.ui.fg
          }
          Text {
            id: linesT
            anchors.right: parent.right
            anchors.rightMargin: lb.ui.space(150)
            anchors.verticalCenter: parent.verticalCenter
            text: String(row.e.lines | 0)
            font.family: lb.ui.sans
            font.pixelSize: lb.ui.fontBody
            color: lb.ui.dim
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: lb.ui.space(96)
            anchors.verticalCenter: parent.verticalCenter
            text: "x" + (row.e.maxCombo | 0)
            font.family: lb.ui.sans
            font.pixelSize: lb.ui.fontBody
            color: lb.ui.dim
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Game.fmt(row.e.score || 0)
            font.family: lb.ui.sans
            font.pixelSize: lb.ui.fontSubtitle
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
    spacing: lb.ui.space(6)
    Rectangle { width: parent.width; height: 1; color: lb.ui.hairline }
    Item { width: 1; height: lb.ui.space(2) }
    Text {
      width: parent.width
      text: !lb.enabled ? "Nothing is sent while it is off."
        : lb.myTag ? "You are @" + lb.myTag + (lb.myRank ? "   ·   #" + lb.myRank + " all time   ·   best " + Game.fmt(lb.myBest) : "")
        : "Claim a gamer tag to post runs:  :tag NAME"
      elide: Text.ElideRight
      font.family: lb.ui.sans
      font.pixelSize: lb.ui.fontBody
      color: lb.myTag ? lb.ui.fg : lb.ui.dim
    }
    Text {
      visible: lb.enabled
      text: lb.players + " players   ·   " + lb.games + " games"
      font.family: lb.ui.sans
      font.pixelSize: lb.ui.fontSmall
      color: lb.ui.dim
    }
  }
}
