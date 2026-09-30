import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ModelStore.js" as Store

Panel {
  id: root
  moduleName: "org.omaviz.visualizer"
  ipcTarget: "org.omaviz.visualizer"
  manageIpc: false

  // Live config binding — refreshed when hostWidget.config changes (via noteWrite)
  readonly property var hcfg: root.hostWidget ? root.hostWidget.config : Store.defaultConfig()
  property var anchorItem: null
  property var hostWidget: null

  // Panel foreground palette — the panel is hosted by the bar (bar.foreground)
  // or runs detached (shell Color.foreground). Defined ONCE, used ~18 times.
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color fgMuted: Qt.darker(fg, 1.4)
  readonly property color fgFaint: Qt.darker(fg, 1.6)

  readonly property string sourceLabelText:
    root.hostWidget ? root.hostWidget.sourceLabel : "Unknown"

  readonly property bool isScope: root.hcfg.scope === true
  readonly property bool isSpectrum: !root.isScope

  // ---- Derived option state (one concept each) ----
  readonly property bool peaksOn: root.hcfg.peaks !== false
  readonly property bool spikesOn: root.hcfg.spikes === true
  readonly property bool stacksOn: root.hcfg.stacks === true
  readonly property bool fireOn: root.hcfg.fire === true
  readonly property bool customOn: root.hcfg.barColorCustom === true
  // Geometry is a single choice: Bars (default) / Spikes / Stacks.
  readonly property bool barsGeom: !root.spikesOn && !root.stacksOn
  // Gradient direction for the bar field.
  readonly property string gradDir:
    root.hcfg.barGradientDir === "horizontal" ? "horizontal" : "vertical"
  // Each colour mode edits its own persisted tones.
  readonly property bool tonesActive: root.customOn || root.fireOn

  property bool showAdvanced: false

  // Bind to the live config object, not to Store.sharedConfig: a plain JS
  // object property is not observable, and sharedConfig lagged the real
  // config — so the switch showed a stale value until something else forced
  // a re-evaluation. hcfg is a fresh object per config load, so this updates.
  readonly property bool vizEnabled: root.hcfg ? (root.hcfg.enabled !== false) : true
  function setVizEnabled(v) {
    // Do NOT assign vizEnabled imperatively — that would break the reactive
    // binding above. Writing through the host is enough: the config reload
    // pushes the new value back into hcfg.
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
            foreground: root.fg
            accent: Color.accent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.setVizEnabled(!checked)
          }
          Text {
            text: root.vizEnabled ? "ON" : "OFF"
            color: root.vizEnabled ? Color.accent : root.fgFaint
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
          visible: !root.vizEnabled
          text: "Turn on to see all options"
          color: root.fgFaint
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
    id: contentComponent
    Column {
      width: parent ? parent.width : 0
      spacing: Style.space(8)

      // ============================================================
      //  VISUALIZATIONS — two cards (Spectrum / Oscilloscope)
      // ============================================================
      PanelSectionHeader { text: "VISUALIZATIONS" }

      Row {
        width: parent.width
        spacing: Style.space(8)

        VizCard {
          labelText: "SPECTRUM"
          cardSelected: root.isSpectrum
          onCardClicked: if (root.hostWidget) root.hostWidget.writeVizOption("scope", false)
        }

        VizCard {
          labelText: "OSCILLOSCOPE"
          cardSelected: root.isScope
          onCardClicked: if (root.hostWidget) root.hostWidget.writeVizOption("scope", true)
        }
      }

      // ============================================================
      //  PREVIEW — live canvas
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
          wash: root.hcfg.artwork !== false
          reflect: root.hcfg.reflect === true
          scopeLineWidth: (root.hcfg.scopeThickness ?? 2)
          colorSync: root.hcfg.colorSync !== false
          barCount: 64
          gapPx: root.hostWidget ? Math.min(6, Math.max(0, root.hostWidget.barGap)) : 1
          peaks: root.peaksOn
          peakFalloff: (root.hcfg.peakFalloff ?? 0.1)
          peakSustainMs: (root.hcfg.peakSustainMs ?? 100)
          linearFall: root.hcfg.linearFall !== false
          noiseFloor: 0.02
          spikes: root.spikesOn
          fire: root.fireOn
          fireColorFrom: root.hcfg.fireColorFrom || "#be1400"
          fireColorTo: root.hcfg.fireColorTo || "#fde047"
          stacks: root.stacksOn
          sensitivity: (root.hcfg.sensitivity ?? 1.0)
          barColorCustom: root.customOn
          barColorFrom: root.hcfg.barColorFrom || "#e68e0d"
          barColorTo: root.hcfg.barColorTo || "#f59e0b"
          gradientDir: root.gradDir
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
        color: root.fgFaint
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        width: parent.width
        horizontalAlignment: Text.AlignLeft
      }

      // ============================================================
      //  LOOK — shape of the bars (Spectrum only)
      // ============================================================
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.isSpectrum

        PanelSeparator { }
        PanelSectionHeader { text: "LOOK" }

        // Geometry — one choice: Bars / Spikes / Stacks
        Column {
          width: parent.width
          spacing: Style.space(4)
          Text {
            text: "Geometry"
            color: root.fgMuted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            width: parent.width
            elide: Text.ElideRight
          }
          Row {
            id: geomRow
            width: parent.width
            spacing: Style.space(6)
            Chip {
              width: (geomRow.width - Style.space(12)) / 3
              chipLabel: "Bars"
              selected: root.barsGeom
              onChipClicked: if (root.hostWidget) root.hostWidget.writeVizOptions3("spikes", false, "stacks", false)
            }
            Chip {
              width: (geomRow.width - Style.space(12)) / 3
              chipLabel: "Spikes"
              selected: root.spikesOn
              onChipClicked: if (root.hostWidget) root.hostWidget.writeVizOptions3("spikes", true, "stacks", false)
            }
            Chip {
              width: (geomRow.width - Style.space(12)) / 3
              chipLabel: "Stacks"
              selected: root.stacksOn
              onChipClicked: if (root.hostWidget) root.hostWidget.writeVizOptions3("stacks", true, "spikes", false)
            }
          }
        }

        // Peaks + fall speed (fall speed is the only "drop" control; the
        // fixed-rate drop lives in Advanced as "Linear fall").
        Row {
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
                color: root.fg
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
                value: (root.hcfg.peakFalloff ?? 0.1)
                onReleased: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption("peak_falloff", Math.round(v * 20) / 20) }
              }
            }
          }
        }

        Toggle {
          width: parent.width
          label: "Reflection"
          description: "Floor mirror"
          checked: root.hcfg.reflect === true
          onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("reflect", !checked)
        }
      }

      // ============================================================
      //  COLOR — mode, tones, direction, presets
      // ============================================================
      PanelSeparator { }
      PanelSectionHeader { text: "COLOR" }

      Column {
        width: parent.width
        spacing: Style.space(4)
        Text {
          text: "Color mode"
          color: root.fgMuted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          width: parent.width
          elide: Text.ElideRight
        }
        Row {
          id: modeRow
          width: parent.width
          spacing: Style.space(6)
          Chip {
            width: (modeRow.width - Style.space(12)) / 3
            chipLabel: "Theme"
            selected: !root.fireOn && !root.customOn
            onChipClicked: if (root.hostWidget) root.hostWidget.writeVizOptions("fire", false, "bar_color_custom", false)
          }
          Chip {
            width: (modeRow.width - Style.space(12)) / 3
            chipLabel: "Custom"
            selected: !root.fireOn && root.customOn
            onChipClicked: if (root.hostWidget) root.hostWidget.writeVizOptions("fire", false, "bar_color_custom", true)
          }
          Chip {
            width: (modeRow.width - Style.space(12)) / 3
            chipLabel: "Flame"
            selected: root.fireOn
            onChipClicked: if (root.hostWidget) root.hostWidget.writeVizOption("fire", true)
          }
        }
      }

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

          Column {
            width: parent.width
            spacing: Style.space(4)
            enabled: root.tonesActive
            opacity: root.tonesActive ? 1.0 : 0.45

            Text {
              text: root.fireOn ? "Flame tones" : "Custom tones"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              width: parent.width
              elide: Text.ElideRight
            }
            Text {
              text: root.fireOn ? "From (base) · To (flame tip)" : "From (base) · To (tip)"
              color: root.fgMuted
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
                value: root.fireOn ? root.hcfg.fireColorFrom : root.hcfg.barColorFrom
                onAccept: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption(root.fireOn ? "fire_color_from" : "bar_color_from", v) }
              }
              HexField {
                width: (parent.width - Style.space(8)) / 2
                value: root.fireOn ? root.hcfg.fireColorTo : root.hcfg.barColorTo
                onAccept: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption(root.fireOn ? "fire_color_to" : "bar_color_to", v) }
              }
            }
          }

          // Gradient direction: bottom->top (default) or left->right.
          Column {
            width: parent.width
            spacing: Style.space(4)
            Text {
              text: "Gradient direction"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              width: parent.width
              elide: Text.ElideRight
            }
            Row {
              id: dirRow
              width: parent.width
              spacing: Style.space(6)
              Chip {
                width: (dirRow.width - Style.space(6)) / 2
                chipLabel: "Vertical"
                selected: root.gradDir === "vertical"
                onChipClicked: if (root.hostWidget) root.hostWidget.writeVizOption("bar_gradient_dir", "vertical")
              }
              Chip {
                width: (dirRow.width - Style.space(6)) / 2
                chipLabel: "Horizontal"
                selected: root.gradDir === "horizontal"
                onChipClicked: if (root.hostWidget) root.hostWidget.writeVizOption("bar_gradient_dir", "horizontal")
              }
            }
          }

          // Preset swatches — 8 gradients + Fire.
          Row {
            id: presetRow
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: [["#e68e0d","#f59e0b"],["#ef4444","#f59e0b"],["#0369a1","#38bdf8"],["#7c3aed","#c4b5fd"],["#65a30d","#d9f99d"],["#e11d48","#fda4af"],["#06b6d4","#a5f3fc"],["#6b7280","#f8fafc"]]
              Rectangle {
                width: (presetRow.width - Style.space(66)) / 9
                height: 22
                radius: 5
                gradient: Gradient {
                  GradientStop { position: 0.0; color: modelData[0] }
                  GradientStop { position: 1.0; color: modelData[1] }
                }
                border.width: (!root.fireOn && root.customOn && root.hcfg.barColorFrom === modelData[0] && root.hcfg.barColorTo === modelData[1]) ? 2 : 0
                border.color: Color.accent
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.hostWidget) root.hostWidget.writeVizOptions3("fire", false, "bar_color_custom", true, "bar_color_from", modelData[0], "bar_color_to", modelData[1])
                }
              }
            }
            // Fire swatch — selecting it switches to Flame colour mode.
            Rectangle {
              width: (presetRow.width - Style.space(66)) / 9
              height: 22
              radius: 5
              gradient: Gradient {
                GradientStop { position: 0.0; color: "#450a0a" }
                GradientStop { position: 0.45; color: "#b91c1c" }
                GradientStop { position: 0.75; color: "#f97316" }
                GradientStop { position: 1.0; color: "#fde047" }
              }
              border.width: root.fireOn ? 2 : 0
              border.color: Color.accent
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("fire", true)
              }
            }
          }
          Text {
            text: "Tap a preset or type hex · applies to mini, preview, desktop + wave."
            color: root.fgMuted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            width: parent.width
            elide: Text.ElideRight
          }
        }
      }

      // ============================================================
      //  MOTION — reactivity (bars + wave) and mono
      // ============================================================
      PanelSeparator { }
      PanelSectionHeader { text: "MOTION" }

      Row {
        width: parent.width
        spacing: Style.space(14)
        BorderSurface {
          width: (parent.width - Style.space(14)) / 2
          height: respCol.implicitHeight + Style.spacing.huge
          radius: Style.cornerRadius
          color: Style.controlFill(false, false, Color.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
          Column {
            id: respCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: parent.borderLeft + Style.spacing.rowPaddingX
            anchors.rightMargin: parent.borderRight + Style.spacing.rowPaddingX
            spacing: Style.space(4)
            Text {
              text: "Response"
              color: root.fg
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
      Text {
        text: "Response scales bar reactivity and waveform amplitude with input gain."
        color: root.fgMuted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        width: parent.width
        wrapMode: Text.WordWrap
      }

      // ============================================================
      //  SCOPE — waveform thickness (Oscilloscope only)
      // ============================================================
      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: root.isScope

        PanelSeparator { }
        PanelSectionHeader { text: "OSCILLOSCOPE" }
        Text {
          text: "Line thickness"
          color: root.fg
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

      // ============================================================
      //  ADVANCED — collapsed; rarely-touched controls
      // ============================================================
      PanelSeparator { }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Text {
          text: "ADVANCED"
          color: root.fgMuted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          topPadding: Math.ceil(Style.font.caption * 0.15)
          width: parent.width - advLink.width - parent.spacing
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          id: advLink
          text: root.showAdvanced ? "Hide" : "Show"
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

      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.showAdvanced

        Row {
          width: parent.width
          spacing: Style.space(14)

          Toggle {
            width: (parent.width - Style.space(14)) / 2
            label: "Linear fall"
            description: "Fixed-rate drop"
            checked: root.hcfg.linearFall === true
            onClicked: if (root.hostWidget) root.hostWidget.writeEngineOption("linear_fall", !checked)
          }

          Toggle {
            width: (parent.width - Style.space(14)) / 2
            label: "Dots"
            description: "Faint dot grid"
            checked: root.hcfg.dots !== false
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("dots", !checked)
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(14)

          Toggle {
            width: (parent.width - Style.space(14)) / 2
            label: "Artwork backdrop"
            description: "Immersive backdrop"
            checked: root.hcfg.artwork !== false
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("artwork", !checked)
          }

          Toggle {
            width: (parent.width - Style.space(14)) / 2
            label: "GPU"
            description: "Hardware painting"
            checked: root.hcfg.gpu !== false
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("gpu", !checked)
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
          color: root.fgMuted
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

  // ---- Reusable components ----
  component VizCard: Item {
    id: card
    property string labelText: ""
    property bool cardSelected: false
    signal cardClicked()

    width: (parent ? (parent.width - Style.space(8)) / 2 : 200)
    height: 46

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      border.width: 1
      border.color: card.cardSelected ? Color.accent : Qt.rgba(1,1,1,0.08)
      color: card.cardSelected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14) : Color.popups.background

      Text {
        anchors.centerIn: parent
        text: card.labelText
        font.family: Style.font.family
        font.pixelSize: 13
        font.bold: true
        font.letterSpacing: 1.5
        color: card.cardSelected ? Color.accent : (root.fg)
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: card.cardClicked()
    }
  }

  component Chip: Item {
    id: chip
    property string chipLabel: ""
    property bool selected: false
    signal chipClicked()

    height: 30

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      border.width: 1
      border.color: chip.selected ? Color.accent : Qt.rgba(1,1,1,0.10)
      color: chip.selected
        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
        : Qt.rgba(1,1,1,0.05)

      Text {
        anchors.centerIn: parent
        text: chip.chipLabel
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        color: chip.selected ? Color.accent : root.fg
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.chipClicked()
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
          color: root.fg
          font.family: "monospace"
          font.pixelSize: Style.font.bodySmall
          maximumLength: 7
          validator: RegularExpressionValidator {
            regularExpression: /^#[0-9a-fA-F]{0,6}$/
          }
          onEditingFinished: hexField.submit(text)
        }
      }
    }
  }
}
