import QtQuick
import QtQuick.Controls

Item {
  id: choices
  property var options: []
  property string selected: ""
  property string label: "Choices"
  property color foreground: "#eeeeee"
  property color accent: "#55aaff"
  signal chosen(string value)
  signal focused(var item)
  implicitHeight: 36
  readonly property bool compact: options.length < 5
  Row {
    anchors.fill: parent; spacing: 6; visible: choices.compact
    Repeater {
      model: choices.compact ? choices.options : []
      Button {
        required property var modelData
        objectName: "choice-" + modelData.id
        width: (choices.width - Math.max(0,choices.options.length-1)*6) / Math.max(1,choices.options.length)
        height: choices.height
        text: modelData.label
        checked: choices.selected === modelData.id
        Accessible.role: Accessible.RadioButton
        Accessible.name: choices.label + ": " + text
        Accessible.checked: checked
        onActiveFocusChanged: if (activeFocus) choices.focused(this)
        onClicked: choices.chosen(modelData.id)
        contentItem: Text { text: parent.text; color: choices.foreground; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.pixelSize: 12 }
        background: Rectangle {
          radius: 0
          color: parent.checked ? Qt.rgba(choices.accent.r,choices.accent.g,choices.accent.b,0.20) : "#10ffffff"
          border.color: parent.activeFocus || parent.checked ? choices.accent : "#30ffffff"
        }
      }
    }
  }
  ComboBox {
    id: dropdown; objectName: "choices-dropdown"
    anchors.fill: parent; visible: !choices.compact
    model: choices.options
    textRole: "label"; valueRole: "id"
    currentIndex: { for(var i=0;i<choices.options.length;i++) if(choices.options[i].id === choices.selected) return i; return -1 }
    Accessible.name: choices.label
    onActiveFocusChanged: if (activeFocus) choices.focused(this)
    onActivated: choices.chosen(currentValue)
    contentItem: Text {
      text: dropdown.displayText; color: choices.foreground
      leftPadding: 12; rightPadding: 28; verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight; font.pixelSize: 12
    }
    indicator: Text { text: "⌄"; color: choices.foreground; x: dropdown.width-22; anchors.verticalCenter: parent.verticalCenter }
    background: Rectangle { radius: 0; color: "#14ffffff"; border.color: dropdown.activeFocus ? choices.accent : "#30ffffff" }
    delegate: ItemDelegate {
      required property int index
      required property var modelData
      width: dropdown.width
      text: modelData.label
      highlighted: dropdown.highlightedIndex === index
      contentItem: Text { text: parent.text; color: choices.foreground; font.pixelSize: 12 }
      background: Rectangle { color: parent.highlighted ? Qt.darker(choices.accent,2) : "#20232a" }
    }
    popup: Popup {
      y: dropdown.height+4; width: dropdown.width
      implicitHeight: Math.min(240, popupList.contentHeight+8)
      padding: 4
      background: Rectangle { color: "#20232a"; radius: 0; border.color: "#40ffffff" }
      contentItem: ListView {
        id: popupList; clip: true
        model: dropdown.popup.visible ? dropdown.delegateModel : null
        currentIndex: dropdown.highlightedIndex
        ScrollIndicator.vertical: ScrollIndicator {}
      }
    }
  }
}
