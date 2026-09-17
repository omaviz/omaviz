import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omaviz settings panel: VISUALIZATIONS → PREVIEW → OPTIONS.
// Visual workflow: pick Spectrum/Scope cards first, live preview below,
// then per-section options. Artwork is a backdrop toggle (merged into
// Spectrum); Dots/Min-height have no UI (still honored in code).
// Bar color: Theme (default) or custom From→To tones, mini+preview+
// desktop in sync; Mono stays as the mini-only override.
// All writes go through BarWidget (disk + live config at once).

Panel {
  id: root
  moduleName: "org.omaviz.visualizer"
  ipcTarget: "org.omaviz.visualizer"
  manageIpc: false

  // Config alias: live bar config once injected, sane defaults before.
  property var hcfg: root.hostWidget ? root.hostWidget.config : Model.defaultConfig()

  // ---- Injected by BarWidget.injectPanel() ----
  property var anchorItem: null
  property var hostWidget: null
  // `bar` and `settings` are provided by the Panel base and overwritten by
  // injectPanel(); the base binding covers pre-injection.

  readonly property string sourceLabelText:
    Model.sourceLabel(Model.spectrumData.source || "")

  // Two visualizations only (Artwork merged into Spectrum as a backdrop).
  readonly property bool isScope: root.hcfg.scope === true
  readonly property bool isSpectrum: !root.isScope
  readonly property bool peaksOn: root.hcfg.peaks !== false
  readonly property bool spikesOn: root.hcfg.spikes === true
  // Main <-> Advanced options views (top viz cards + preview stay put).
  property bool showAdvanced: false

  // ---- Popup lifecycle (Panel base owns controller; do NOT override opened/open/close/toggle) ----
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
          text: "Double-click preview to open full-screen visualization"
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
        // OPTIONS header with nav link in one row: same screen location
        // whether main ("Advanced »") or advanced ("« Back") is showing.
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

        // ---- Options stage: main <-> advanced slide (top stays intact) ----
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

            // Top margin: the sliding stage clips, so first-row top
            // borders would be cut without breathing room.
            Item { width: parent.width; height: Style.space(8) }

            // ---- Bars (spectrum): no subtitle, rows speak for themselves ----

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

        // ---- Bar color (always visible; mini+preview+desktop in sync) ----
        PanelSectionHeader { text: "BAR COLOR" }

        // ---- Bar color: toggle + tones + swatches in one box ----
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

              // Plain label + switch (no Toggle box): the parent color
              // box already provides the container.
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

      // ---- Advanced view (slides in; top viz cards + preview stay put) ----
      Column {
        id: advView
        width: parent.width
        spacing: Style.space(8)
        x: root.showAdvanced ? 0 : 40
        opacity: root.showAdvanced ? 1 : 0
        enabled: root.showAdvanced
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 160 } }

        // Same top margin as main view (shared clipped stage).
        Item { width: parent.width; height: Style.space(8) }

        // Back lives in the shared OPTIONS header row (same spot as
        // "Advanced »") — no separate back link or subtitle here.

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

        // ---- Input gain + Mono side by side (half widths) ----
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

        // ---- Footer: read-only source ----
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

    // NOTE: no Component.onCompleted config reload — the panel is read-only
    // (ADR-0008) and owns no FileView.
  }

  // Size-freeze logic: poll open state; freeze panel size shortly after open
  // so content changes don't jitter the dialog.
  // Timers live at root level — KeyboardPanel's contentItem only takes Items.
  Timer {
    id: lockPoll
    interval: 100; repeat: true; running: true
    onTriggered: {
      if (panel.open) {
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
      if (panel.open && !panel._sizeLocked) {
        panel._frozenH = panel.contentHeight
        panel._sizeLocked = true
      }
    }
  }

  // ---- Reusable inline components (inside Panel root: file-scope
  // `component` declarations fail to load in this shell context) ----

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

  // Hex color field with swatch: validates #rrggbb on accept, reverts
  // to the bound value on invalid input. Callback via plain var prop
  // (signals named on* collide with handler syntax — never again).
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
