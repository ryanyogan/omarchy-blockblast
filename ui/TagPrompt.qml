import QtQuick
import "../Game.js" as Game

// Claim a gamer tag. That is the whole sign-up.
Item {
  id: prompt
  required property var ui
  property string error: ""
  property bool busy: false
  property string currentTag: ""

  signal submitted(string tag)
  signal cancelled()

  readonly property bool valid: Game.validTag(input.text.trim())

  function takeFocus() { input.forceActiveFocus(); input.selectAll() }
  function reset(prefill) { input.text = prefill || ""; error = "" }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) { cancelled(); event.accepted = true; return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (valid && !busy) submitted(input.text.trim())
      else shake.restart()
      event.accepted = true
      return true
    }
    return false
  }

  SequentialAnimation {
    id: shake
    NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: -8; duration: 40 }
    NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: 8; duration: 80 }
    NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
  }

  Column {
    anchors.centerIn: parent
    width: parent.width
    spacing: prompt.ui.space(14)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: prompt.currentTag ? "CHANGE GAMER TAG" : "PICK A GAMER TAG"
      font.family: prompt.ui.font
      font.pixelSize: prompt.ui.fontSmall
      font.letterSpacing: 4
      color: prompt.ui.dim
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: "It goes on the global leaderboard next to your scores. Nothing else is collected."
      font.family: prompt.ui.sans
      font.pixelSize: prompt.ui.fontBody
      color: prompt.ui.fg
    }

    Rectangle {
      id: box
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(parent.width, prompt.ui.space(320))
      height: prompt.ui.space(48)
      radius: prompt.ui.space(10)
      color: prompt.ui.well
      border.width: 2
      border.color: input.text.length ? (prompt.valid ? prompt.ui.accent : prompt.ui.urgent) : prompt.ui.hairline
      Behavior on border.color { ColorAnimation { duration: 120 } }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: prompt.ui.space(16)
        anchors.verticalCenter: parent.verticalCenter
        text: "@"
        font.family: prompt.ui.font
        font.pixelSize: prompt.ui.fontHeading
        color: prompt.ui.dim
      }
      TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: prompt.ui.space(40)
        anchors.rightMargin: prompt.ui.space(16)
        verticalAlignment: TextInput.AlignVCenter
        font.family: prompt.ui.font
        font.pixelSize: prompt.ui.fontHeading
        font.weight: Font.Bold
        color: prompt.ui.fg
        selectionColor: prompt.ui.accent
        selectedTextColor: prompt.ui.onAccent
        maximumLength: 16
        validator: RegularExpressionValidator { regularExpression: /[A-Za-z0-9_-]{0,16}/ }
        enabled: !prompt.busy
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { prompt.handleKey(event) }
        onTextChanged: prompt.error = ""
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: prompt.busy ? "claiming…" : prompt.error ? prompt.error : "2 to 16 letters, numbers, _ or -   ·   enter to claim   ·   esc to skip"
      font.family: prompt.ui.font
      font.pixelSize: prompt.ui.fontSmall
      color: prompt.error ? prompt.ui.urgent : prompt.ui.dim
    }
  }
}
