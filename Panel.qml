import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "org.omaviz.visualizer"
  ipcTarget: "org.omaviz.visualizer"
  manageIpc: false

  property var hcfg: root.hostWidget ? root.hostWidget.config : Model.defaultConfig()
  property var anchorItem: null
  property var hostWidget: null

  readonly property string sourceLabelText:
    Model.sourceLabel(Model.spectrumData.source || "")

  readonly property bool isScope: root.hcfg.scope === true
  readonly property bool isSpectrum: !root.isScope
  readonly property bool peaksOn: root.hcfg.peaks !== false
  readonly property bool spikesOn: root.hcfg.spikes === true
  property bool showAdvanced: false
  property bool vizEnabled: Model.getSharedConfig().enabled !== false
  function setVizEnabled(v) {
    vizEnabled = v
    if (root.hostWidget && root.hostWidget.writeEnabled) root.hostWidget.writeEnabled(v)
  }

  // ---- Size-freeze logic (at root level, NOT inside KeyboardPanel) ----
  Timer {
    id: lockPoll
    interval: 100; repeat: true; running: true
    onTriggered: {
      if (panel.open) {
        if (!root.vizEnabled) return
        if (!panel._sizeLocked) lockTimer.restart()
      } else {
        panel._sizeLocked = false
        panel._frozenH = 0
      }
    }
  }
  Timer {
    id: lockTimer
    interval: 300
    onTriggered: {
      if (!root.vizEnabled) return
      if (panel.open && !panel._sizeLocked) {
        panel._frozenH = panel.contentHeight
        panel._sizeLocked = true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    padding: Math.round(Style.spacing.popupPadding * 2)
    focusTarget: keyCatcher
    property bool _sizeLocked: false
    property int _frozenH: 0
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: _sizeLocked ? _frozenH : panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.close()
    }

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: column
        width: parent.width
        spacing: Style.space(8)

        // ---- ON/OFF toggle (always visible) ----
        Item {
          width: parent.width
          height: Style.space(24)
          ToggleSwitch {
            id: onOffSwitch
            checked: root.vizEnabled
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: Color.accent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.setVizEnabled(!checked)
          }
          Text {
            text: root.vizEnabled ? "ON" : "OFF"
            color: root.vizEnabled ? Color.accent : Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            anchors.right: onOffSwitch.left
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: onOffSwitch.verticalCenter
          }
        }

        // ---- Helper text when OFF ----
        Text {
          width: parent.width
          height: root.vizEnabled ? 0 : implicitHeight
          visible: !root.vizEnabled
          text: "Turn on to see all options"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignCenter
        }

        // ---- Heavy content (loaded only when ON) ----
        Loader {
          id: contentLoader
          width: parent.width
          active: root.vizEnabled
          sourceComponent: contentComponent
        }
      }
    }

  }

  // ---- Heavy content component (loaded only when ON) ----
  Component {
  // ---- Heavy content component (loaded only when ON) ----
  Component {
    id: contentComponent
    Column {
      width: parent ? parent.width : 0
      spacing: Style.space(8)
          Column {
            width: parent ? parent.width : 0
            spacing: Style.space(8)
      
            // ============================================================
            //  VISUALIZATIONS — two cards (Spectrum / Scope)
            // ============================================================
            PanelSectionHeader { text: "VISUALIZATIONS" }
      
            Row {
              width: parent.width
              spacing: Style.space(8)
      
              VizCard {
                labelText: "SPECTRUM"
                selected: root.isSpectrum
                onCardClicked: if (root.hostWidget) root.hostWidget.writeVizOption("scope", false)
              }
      
              VizCard {
                labelText: "OSCILLOSCOPE"
                selected: root.isScope
                onCardClicked: if (root.hostWidget) root.hostWidget.writeVizOption("scope", true)
              }
            }
      
            // ============================================================
            //  PREVIEW — live canvas between Visualizations and Options
            // ============================================================
            PanelSectionHeader { text: "PREVIEW" }
      
            Rectangle {
              width: parent.width
              height: Style.space(60)
              color: Color.popups.background
              radius: Style.cornerRadius
              border.width: 1
              border.color: Qt.rgba(1,1,1,0.08)
      
              DotsCanvas {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                visible: root.hcfg.dots !== false
              }
              VisualCanvas {
                id: previewViz
                anchors.fill: parent
                anchors.margins: Style.space(6)
                dots: false
                bands: root.hostWidget ? root.hostWidget.spectrumBands : []
                silent: root.hostWidget ? root.hostWidget.spectrumSilent : true
                wave: root.hostWidget ? root.hostWidget.spectrumWave : []
                visual: root.isScope ? "Oscilloscope" : "Bars"
                artMode: false
                wash: root.hcfg.artwork !== false
                reflect: root.hcfg.reflect === true
                scopeLineWidth: (root.hcfg.scopeThickness ?? 2)
                colorSync: false
                barCount: 64
                gapPx: root.hostWidget ? Math.min(6, Math.max(0, root.hostWidget.barGap)) : 1
                peaks: root.peaksOn
                peakFalloff: (root.hcfg.peakFalloff ?? 0.5)
                spikes: root.spikesOn
                fire: root.hcfg.fire === true
                stacks: root.hcfg.stacks === true
                sensitivity: (root.hcfg.sensitivity ?? 1.0)
                barColorCustom: root.hcfg.barColorCustom === true
                barColorFrom: root.hcfg.barColorFrom || "#e68e0d"
                barColorTo: root.hcfg.barColorTo || "#f59e0b"
                themeBottom: Qt.darker(Color.accent, 1.3)
                themeTop: Color.accent
              }
              MouseArea {
                anchors.fill: parent
                onClicked: { if (root.hostWidget) root.hostWidget.detach() }
              }
            }
            Text {
              text: "Click preview to open full-screen visualization"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              width: parent.width
              horizontalAlignment: Text.AlignLeft
            }
      
            PanelSeparator { }
      
            // ============================================================
            //  OPTIONS
            // ============================================================
            Row {
              width: parent.width
              spacing: Style.space(8)
              Text {
                text: "OPTIONS"
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                topPadding: Math.ceil(Style.font.caption * 0.15)
                width: parent.width - navLink.width - parent.spacing
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: navLink
                text: root.showAdvanced ? "« Back" : "Advanced »"
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showAdvanced = !root.showAdvanced
                }
              }
            }
      
            // ---- Options stage ----
            Item {
              id: optStage
              width: parent.width
              height: root.showAdvanced ? advView.implicitHeight : mainView.implicitHeight
              Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
              clip: true
      
              Column {
                id: mainView
                width: parent.width
                spacing: Style.space(8)
                x: root.showAdvanced ? -40 : 0
                opacity: root.showAdvanced ? 0 : 1
                enabled: !root.showAdvanced
                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 160 } }
      
                Item { width: parent.width; height: Style.space(8) }
      
                Row {
                  visible: root.isSpectrum
                  width: parent.width
                  spacing: Style.space(14)
      
                  Toggle {
                    width: (parent.width - Style.space(14)) / 2
                    label: "Peaks"
                    description: "Peak-hold markers"
                    checked: root.peaksOn
                    onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("peaks", !checked)
                  }
      
                  BorderSurface {
                    width: (parent.width - Style.space(14)) / 2
                    height: fallCol.implicitHeight + Style.spacing.huge
                    radius: Style.cornerRadius
                    color: Style.controlFill(false, false, Color.foreground, Color.accent)
                    borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
                    Column {
                      id: fallCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: parent.borderLeft + Style.spacing.rowPaddingX
                      anchors.rightMargin: parent.borderRight + Style.spacing.rowPaddingX
                      spacing: Style.space(4)
                      Text {
                        text: "Peak fall speed"
                        color: root.bar ? root.bar.foreground : Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        width: parent.width
                        elide: Text.ElideRight
                      }
                      PanelSlider {
                        width: parent.width
                        bar: root.bar
                        enabled: root.peaksOn
                        minimum: 0; maximum: 1; step: 0.05
                        value: (root.hcfg.peakFalloff ?? 0.5)
                        onReleased: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption("peak_falloff", Math.round(v * 20) / 20) }
                      }
                    }
                  }
                }
      
                Row {
                  visible: root.isSpectrum
                  width: parent.width
                  spacing: Style.space(14)
      
                  Toggle {
                    width: (parent.width - Style.space(14)) / 2
                    label: "Reflection"
                    description: "Floor mirror"
                    checked: root.hcfg.reflect === true
                    onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("reflect", !checked)
                  }
      
                  Toggle {
                    width: (parent.width - Style.space(14)) / 2
                    label: "Artwork backdrop"
                    description: "Immersive artwork"
                    checked: root.hcfg.artwork !== false
                    onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("artwork", !checked)
                  }
                }
      
                PanelSectionHeader { text: "BAR COLOR" }
      
                BorderSurface {
                  width: parent.width
                  height: colorBoxCol.implicitHeight + Style.spacing.huge
                  radius: Style.cornerRadius
                  color: Style.controlFill(false, false, Color.foreground, Color.accent)
                  borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
                  Column {
                    id: colorBoxCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: parent.borderLeft + Style.spacing.rowPaddingX
                    anchors.rightMargin: parent.borderRight + Style.spacing.rowPaddingX
                    spacing: Style.space(8)
                    Row {
                      width: parent.width
                      spacing: Style.space(14)
      
                      // Plain label + switch (no Toggle box)
                      Row {
                        width: (parent.width - Style.space(14)) / 2
                        spacing: Style.space(8)
                        Column {
                          width: parent.width - customSwitch.width - parent.spacing
                          spacing: Style.space(4)
                          anchors.verticalCenter: parent.verticalCenter
                          Text {
                            text: "Custom colors"
                            color: root.bar ? root.bar.foreground : Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            font.bold: true
                            width: parent.width
                            elide: Text.ElideRight
                          }
                          Text {
                            text: "Off = theme colors"
                            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                            width: parent.width
                            elide: Text.ElideRight
                          }
                        }
                        ToggleSwitch {
                          id: customSwitch
                          checked: root.hcfg.barColorCustom === true
                          foreground: root.bar ? root.bar.foreground : Color.foreground
                          accent: Color.accent
                          anchors.verticalCenter: parent.verticalCenter
                          onToggled: if (root.hostWidget) root.hostWidget.writeVizOption("bar_color_custom", !checked)
                        }
                      }
      
                      Column {
                        width: (parent.width - Style.space(14)) / 2
                        spacing: Style.space(4)
                        enabled: root.hcfg.barColorCustom === true
                        opacity: root.hcfg.barColorCustom === true ? 1.0 : 0.45
      
                        Text {
                          text: "Custom tones"
                          color: root.bar ? root.bar.foreground : Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.body
                          width: parent.width
                          elide: Text.ElideRight
                        }
                        Text {
                          text: "From (base) · To (tip)"
                          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          width: parent.width
                          elide: Text.ElideRight
                        }
                        Row {
                          width: parent.width
                          spacing: Style.space(8)
      
                          HexField {
                            width: (parent.width - Style.space(8)) / 2
                            value: root.hcfg.barColorFrom || "#e68e0d"
                            onAccept: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption("bar_color_from", v) }
                          }
                          HexField {
                            width: (parent.width - Style.space(8)) / 2
                            value: root.hcfg.barColorTo || "#f59e0b"
                            onAccept: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption("bar_color_to", v) }
                          }
                        }
                      }
                    }
                    Row {
                      id: presetRow
                      width: parent.width
                      spacing: Style.space(6)
                      Repeater {
                        model: [["#e68e0d","#f59e0b"],["#ef4444","#f59e0b"],["#0369a1","#38bdf8"],["#7c3aed","#c4b5fd"],["#65a30d","#d9f99d"],["#e11d48","#fda4af"],["#06b6d4","#a5f3fc"],["#6b7280","#f8fafc"]]
                        Rectangle {
                          width: (presetRow.width - Style.space(42)) / 8
                          height: 22
                          radius: 5
                          gradient: Gradient {
                            GradientStop { position: 0.0; color: modelData[0] }
                            GradientStop { position: 1.0; color: modelData[1] }
                          }
                          border.width: (root.hcfg.barColorFrom === modelData[0] && root.hcfg.barColorTo === modelData[1]) ? 2 : 0
                          border.color: Color.accent
                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.hostWidget) root.hostWidget.writeVizOptions3("bar_color_custom", true, "bar_color_from", modelData[0], "bar_color_to", modelData[1])
                          }
                        }
                      }
                    }
                    Text {
                      text: "Tap a preset or type hex · applies to mini, preview, desktop + wave."
                      color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      width: parent.width
                      elide: Text.ElideRight
                    }
                  }
                }
              }
      
              // ---- Advanced view ----
              Column {
                id: advView
                width: parent.width
                spacing: Style.space(8)
                x: root.showAdvanced ? 0 : 40
                opacity: root.showAdvanced ? 1 : 0
                enabled: root.showAdvanced
                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 160 } }
      
                Item { width: parent.width; height: Style.space(8) }
      
                Row {
                  visible: root.isSpectrum
                  width: parent.width
                  spacing: Style.space(14)
      
                  Toggle {
                    width: (parent.width - Style.space(14)) / 2
                    label: "Spikes"
                    description: "Thin firy spikes"
                    checked: root.spikesOn
                    onClicked: {
                      if (!root.hostWidget) return
                      var v = !checked
                      root.hostWidget.writeVizOptions("spikes", v, "fire", v)
                    }
                  }
      
                  Toggle {
                    width: (parent.width - Style.space(14)) / 2
                    label: "Stacks"
                    description: "Segmented Winamp bars"
                    checked: root.hcfg.stacks === true
                    onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("stacks", !checked)
                  }
                }
      
                Row {
                  width: parent.width
                  spacing: Style.space(14)
      
                  Toggle {
                    width: (parent.width - Style.space(14)) / 2
                    label: "Fire"
                    description: "Flame gradient everywhere"
                    checked: root.hcfg.fire === true
                    onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("fire", !checked)
                  }
      
                  Toggle {
                    width: (parent.width - Style.space(14)) / 2
                    label: "Linear fall"
                    description: "Fixed-rate drop"
                    checked: root.hcfg.linearFall === true
                    onClicked: if (root.hostWidget) root.hostWidget.writeEngineOption("linear_fall", !checked)
                  }
                }
      
                Column {
                  width: parent.width
                  spacing: Style.space(4)
                  visible: root.isScope
                  Text {
                    text: "Waveform. Follows color + input gain."
                    color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    width: parent.width
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    text: "Line thickness"
                    color: root.bar ? root.bar.foreground : Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    width: parent.width
                    elide: Text.ElideRight
                  }
                  BorderSurface {
                    width: parent.width
                    height: thickCol.implicitHeight + Style.spacing.huge
                    radius: Style.cornerRadius
                    color: Style.controlFill(false, false, Color.foreground, Color.accent)
                    borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
                    Column {
                      id: thickCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: parent.borderLeft + Style.spacing.rowPaddingX
                      anchors.rightMargin: parent.borderRight + Style.spacing.rowPaddingX
                      spacing: Style.space(4)
                      PanelSlider {
                        width: parent.width
                        bar: root.bar
                        minimum: 1; maximum: 5; step: 0.5
                        value: (root.hcfg.scopeThickness ?? 2)
                        onReleased: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption("scope_thickness", Math.round(v * 2) / 2) }
                      }
                    }
                  }
                }
      
                // ---- Input gain + Mono ----
                Row {
                  width: parent.width
                  spacing: Style.space(14)
                  BorderSurface {
                    width: (parent.width - Style.space(14)) / 2
                    height: gainCol.implicitHeight + Style.spacing.huge
                    radius: Style.cornerRadius
                    color: Style.controlFill(false, false, Color.foreground, Color.accent)
                    borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
                    Column {
                      id: gainCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: parent.borderLeft + Style.spacing.rowPaddingX
                      anchors.rightMargin: parent.borderRight + Style.spacing.rowPaddingX
                      spacing: Style.space(4)
                      Text {
                        text: "Input gain"
                        color: root.bar ? root.bar.foreground : Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        width: parent.width
                        elide: Text.ElideRight
                      }
                      PanelSlider {
                        width: parent.width
                        bar: root.bar
                        minimum: 0.5; maximum: 2; step: 0.1
                        value: (root.hcfg.sensitivity ?? 1.0)
                        onReleased: function(v) { if (root.hostWidget) root.hostWidget.writeAudioOption("sensitivity", Math.round(v * 10) / 10) }
                      }
                    }
                  }
                  Toggle {
                    width: (parent.width - Style.space(14)) / 2
                    label: "Mono (mini only)"
                    description: "B&W mini bars"
                    checked: root.hcfg.mono === true
                    onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("mono", !checked)
                  }
                }
              }
            }
      
            PanelSeparator { }
      
            // ---- Footer ----
            Row {
              width: parent.width
              spacing: Style.space(8)
              Text {
                text: "SOURCE"
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: root.sourceLabelText + " · default sink"
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }
      
    }
  }
  // ---- Reusable components ----
  component VizCard: Item {
    id: card
    property string labelText: ""
    property bool selected: false
    signal cardClicked()

    width: (parent ? (parent.width - Style.space(8)) / 2 : 200)
    height: 46

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      border.width: 1
      border.color: card.selected ? Color.accent : Qt.rgba(1,1,1,0.08)
      color: card.selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14) : Color.popups.background

      Text {
        anchors.centerIn: parent
        text: card.labelText
        font.family: Style.font.family
        font.pixelSize: 13
        font.bold: true
        font.letterSpacing: 1.5
        color: card.selected ? Color.accent : (root.bar ? root.bar.foreground : Color.foreground)
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: card.cardClicked()
    }
  }

  component HexField: Item {
    id: hexField
    property string value: "#e68e0d"
    property var onAccept: null

    height: 26

    function submit(raw) {
      var v = String(raw).trim()
      if (/^#[0-9a-fA-F]{6}$/.test(v)) {
        if (hexField.onAccept) hexField.onAccept(v)
      } else {
        hexInput.text = hexField.value
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: 5
      color: Qt.rgba(1,1,1,0.04)
      border.width: 1
      border.color: Qt.rgba(1,1,1,0.12)

      Row {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 6

        Rectangle {
          width: 14
          height: 14
          radius: 3
          color: hexField.value
          border.width: 1
          border.color: Qt.rgba(1,1,1,0.2)
          anchors.verticalCenter: parent.verticalCenter
        }

        TextInput {
          id: hexInput
          width: parent.width - 26
          anchors.verticalCenter: parent.verticalCenter
          text: hexField.value
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: "monospace"
          font.pixelSize: Style.font.bodySmall
          maximumLength: 7
          validator: RegularExpressionValidator {
            regularExpression: /^#[0-9a-fA-F]{0,6}$/
          }
          onAccepted: hexField.submit(text)
          onEditingFinished: hexField.submit(text)
        }
      }
    }
  }
}
