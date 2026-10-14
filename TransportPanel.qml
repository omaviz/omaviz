import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

Rectangle {
  id: panel
  property var player: null
  property string fallbackTitle: "Omaviz"
  property string status: "Listening to system audio"
  property bool shown: false
  signal toggleRequested()
  signal previousRequested()
  signal nextRequested()
  signal closeRequested()
  readonly property bool controlsFocused: previousAction.activeFocus || playAction.activeFocus || nextAction.activeFocus || closeAction.activeFocus
  readonly property bool canToggle: !!player && player.canControl && (player.canTogglePlaying || (player.isPlaying ? player.canPause : player.canPlay))
  height: 72
  radius: 10
  color: "#a610141c"
  border.color: "#24ffffff"
  opacity: shown ? 1 : 0
  visible: shown || opacity > 0.01
  enabled: shown
  Behavior on opacity { NumberAnimation { duration: 180 } }
  function focusPlayback() {
    shown = true
    if (playAction.visible) playAction.forceActiveFocus()
    else closeAction.forceActiveFocus()
  }
  Rectangle {
    id: poster
    x: 12; y: 12; width: 48; height: 48
    radius: 5; color: "#382b3341"; clip: true
    Text { anchors.centerIn: parent; text: "♪"; color: "#b9c2d2"; font.pixelSize: 24 }
    Image {
      anchors.fill: parent
      source: panel.player ? panel.player.trackArtUrl || "" : ""
      sourceSize: Qt.size(96, 96)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      visible: status === Image.Ready
    }
  }
  Column {
    anchors.left: poster.right; anchors.leftMargin: 12
    anchors.right: actions.left; anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    visible: width >= 100
    spacing: 4
    Text {
      width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
      text: panel.player ? panel.player.trackTitle || panel.fallbackTitle : panel.fallbackTitle
      font.pixelSize: 13; font.weight: Font.Medium; color: "#eef2fa"
    }
    Text {
      width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
      text: panel.player ? panel.player.trackArtist || panel.player.identity || panel.status : panel.status
      font.pixelSize: 11; color: "#b5bfce"
    }
  }
  Row {
    id: actions
    anchors.right: closeAction.left; anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4
    TransportAction {
      id: previousAction; objectName: "previous"
      visible: !!panel.player && panel.player.canControl && panel.player.canGoPrevious
      label: "previous"; accessibleLabel: "Previous track"
      onTriggered: panel.previousRequested()
    }
    TransportAction {
      id: playAction; objectName: "playback"
      visible: panel.canToggle
      label: panel.player && panel.player.isPlaying ? "Ⅱ" : "▶"
      accessibleLabel: panel.player && panel.player.isPlaying ? "Pause" : "Play"
      onTriggered: panel.toggleRequested()
    }
    TransportAction {
      id: nextAction; objectName: "next"
      visible: !!panel.player && panel.player.canControl && panel.player.canGoNext
      label: "next"; accessibleLabel: "Next track"
      onTriggered: panel.nextRequested()
    }
  }
  TransportAction {
    id: closeAction; objectName: "close"
    anchors.right: parent.right; anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    label: "×"; accessibleLabel: "Close desktop visualizer"
    onTriggered: panel.closeRequested()
  }
  component TransportAction: Rectangle {
    id: action
    property string label: ""
    property string accessibleLabel: ""
    signal triggered()
    width: 32; height: 32; radius: 16
    color: pointer.containsMouse || activeFocus ? "#62546480" : "transparent"
    activeFocusOnTab: visible
    Accessible.role: Accessible.Button
    Accessible.name: accessibleLabel
    Accessible.onPressAction: triggered()
    Keys.onSpacePressed: triggered()
    Keys.onReturnPressed: triggered()
    Text { anchors.centerIn: parent; visible: action.label !== "previous" && action.label !== "next"; text: action.label; color: "#eef2fa"; font.pixelSize: 17 }
    Item {
      anchors.centerIn: parent; width: 16; height: 16
      visible: action.label === "previous" || action.label === "next"
      rotation: action.label === "previous" ? 180 : 0
      Shape {
        anchors.fill: parent
        ShapePath {
          strokeWidth: 0; fillColor: "#eef2fa"
          startX: 3; startY: 3
          PathLine { x: 11; y: 8 }
          PathLine { x: 3; y: 13 }
          PathLine { x: 3; y: 3 }
        }
      }
      Rectangle { x: 12; y: 3; width: 2; height: 10; radius: 0.5; color: "#eef2fa" }
    }
    ToolTip.visible: pointer.containsMouse || activeFocus
    ToolTip.text: accessibleLabel
    MouseArea {
      id: pointer; anchors.fill: parent; hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.triggered()
    }
  }
}
