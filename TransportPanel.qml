import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

Rectangle {
  id: panel
  property var player: null
  property string fallbackTitle: "Omaviz"
  property string status: "Listening to system audio"
  property string creditText: ""
  property url creditUrl
  property bool shown: false
  signal toggleRequested()
  signal previousRequested()
  signal nextRequested()
  signal closeRequested()
  readonly property bool controlsFocused: previousAction.activeFocus || playAction.activeFocus || nextAction.activeFocus || closeAction.activeFocus || credit.activeFocus
  readonly property bool canToggle: !!player && player.canControl && (player.canTogglePlaying || (player.isPlaying ? player.canPause : player.canPlay))
  readonly property bool compact: width < 440
  height: compact ? details.y + details.height + (credit.visible ? credit.height + 6 : 0) + 12
                  : Math.max(details.height, controls.height) + 24
  radius: 0
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
  Row {
    id: details; objectName: "transportDetails"
    anchors.left: parent.left; anchors.leftMargin: 12
    y: panel.compact ? 50 : 12
    width: Math.max(0, panel.width - (panel.compact ? 24 : controls.width + 36))
    spacing: 10
    Rectangle {
      id: poster; objectName: "transportPoster"
      width: panel.compact ? 48 : 64; height: width
      radius: 0; color: "#382b3341"; clip: true
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
      objectName: "transportMetadata"
      width: Math.max(0, details.width - poster.width - details.spacing)
      spacing: 3
      Text {
        objectName: "transportTitle"
        width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
        wrapMode: Text.Wrap; maximumLineCount: panel.compact ? 1 : 2
        text: panel.player ? panel.player.trackTitle || panel.fallbackTitle : panel.fallbackTitle
        font.pixelSize: 13; font.weight: Font.Medium; color: "#eef2fa"
      }
      Text {
        width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
        text: panel.player ? panel.player.trackArtist || panel.player.identity || panel.status : panel.status
        font.pixelSize: 11; color: "#b5bfce"
      }
      Text {
        objectName: "transportAlbum"
        width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
        text: panel.player ? panel.player.trackAlbum || "" : ""
        visible: text !== ""
        font.pixelSize: 11; color: "#b5bfce"
      }
    }
    HoverHandler { id: metadataHover; blocking: false }
    ToolTip.visible: metadataHover.hovered
    ToolTip.delay: 500
    ToolTip.text: panel.player ? [panel.player.trackTitle, panel.player.trackAlbum, panel.player.trackArtist].filter(Boolean).join("\n") : panel.fallbackTitle
  }
  Item {
    id: controls; objectName: "transportControls"
    anchors.right: parent.right; anchors.rightMargin: 12
    y: 12
    width: Math.max(actions.implicitWidth, credit.visible ? 140 : 0)
    height: credit.visible ? credit.y + credit.height : actions.height
    Row {
      id: actions
      objectName: "transportActions"
      anchors.right: parent.right
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
      TransportAction {
        id: closeAction; objectName: "close"
        label: "×"; accessibleLabel: "Close desktop visualizer"
        onTriggered: panel.closeRequested()
      }
    }
    Text {
      id: credit; objectName: "visualizationCredit"
      y: panel.compact ? details.y + details.height + 6 - controls.y : actions.height + 6
      width: parent.width
      visible: panel.creditText !== ""
      text: panel.creditText; textFormat: Text.StyledText
      horizontalAlignment: Text.AlignRight
      wrapMode: Text.Wrap
      color: "#b5bfce"; linkColor: "#b5bfce"; font.pixelSize: 10
      activeFocusOnTab: visible
      Accessible.role: Accessible.Link
      Accessible.name: text.replace(/<br\s*\/?\s*>/g, ", ").replace(/<[^>]+>/g, "")
      Keys.onReturnPressed: Qt.openUrlExternally(panel.creditUrl)
      Keys.onSpacePressed: Qt.openUrlExternally(panel.creditUrl)
      onLinkActivated: link => Qt.openUrlExternally(link)
    }
  }
  component TransportAction: Rectangle {
    id: action
    property string label: ""
    property string accessibleLabel: ""
    signal triggered()
    width: 32; height: 32; radius: 0
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
