import QtQuick
import "../Game.js" as Game

// The end of a run. Score first, then where it landed in the world.
Item {
  id: card
  required property var ui
  property var rec: null          // record from Service.finishGame
  property bool posting: false
  property string postError: ""
  property bool hasTag: false
  property bool leaderboardOn: true
  property int best: 0

  readonly property bool newBest: rec && rec.localBest === true
  readonly property string rankLine: {
    if (!rec) return ""
    if (!leaderboardOn) return "Leaderboard is off. Saved here only."
    if (!hasTag) return "Not posted. Press  r  to claim a gamer tag and post it."
    if (posting) return "posting…"
    if (postError) return "Saved for later: " + postError
    if (rec.posted && rec.rank) {
      var line = "#" + rec.rank + " in the world"
      if (rec.dayRank) line += "  ·  #" + rec.dayRank + " today"
      if (rec.players) line += "  ·  " + rec.players + " players"
      return line
    }
    return rec.posted ? "posted" : "queued"
  }

  function reveal() { if (ui.animated) revealAnim.restart() }

  SequentialAnimation {
    id: revealAnim
    PropertyAction { target: big; property: "scale"; value: 0.3 }
    PropertyAction { target: big; property: "opacity"; value: 0 }
    PropertyAction { target: rest; property: "opacity"; value: 0 }
    ParallelAnimation {
      NumberAnimation { target: big; property: "opacity"; to: 1; duration: 200 }
      NumberAnimation { target: big; property: "scale"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
    }
    NumberAnimation { target: rest; property: "opacity"; to: 1; duration: 300 }
  }

  Column {
    anchors.centerIn: parent
    width: parent.width
    spacing: card.ui.space(8)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: card.newBest ? "NEW BEST" : "GAME OVER"
      font.family: card.ui.font
      font.pixelSize: card.ui.fontSmall
      font.letterSpacing: 4
      color: card.newBest ? card.ui.accent : card.ui.dim
    }
    Text {
      id: big
      anchors.horizontalCenter: parent.horizontalCenter
      text: Game.fmt(card.rec ? card.rec.score : 0)
      font.family: card.ui.font
      font.pixelSize: card.ui.fontHero * 1.6
      font.weight: Font.Black
      color: card.newBest ? card.ui.accent : card.ui.fg
      transformOrigin: Item.Center
    }
    Column {
      id: rest
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: card.ui.space(6)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: card.rec ? (card.rec.lines + " lines  ·  combo x" + card.rec.maxCombo + "  ·  " + card.rec.moves + " moves  ·  best " + Game.fmt(card.best)) : ""
        font.family: card.ui.sans
        font.pixelSize: card.ui.fontBody
        color: card.ui.dim
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: card.rankLine
        font.family: card.ui.font
        font.pixelSize: card.ui.fontSubtitle
        font.weight: Font.Bold
        color: card.postError ? card.ui.urgent : card.ui.fg
      }
      Item { width: 1; height: card.ui.space(10) }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "n  new game      t  leaderboard      q  quit"
        font.family: card.ui.font
        font.pixelSize: card.ui.fontBody
        color: card.ui.dim
      }
    }
  }
}
