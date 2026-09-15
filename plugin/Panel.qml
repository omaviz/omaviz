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
    contentWidth: panel.fittedContentWidth(Style.space(460))
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
            labelText: "Spectrum"
            iconText: "B"
            iconBg: "#e68e0d"
            selected: root.isSpectrum
            onCardClicked: if (root.hostWidget) root.hostWidget.writeVizOption("scope", false)
          }

          VizCard {
            labelText: "Scope"
            iconText: "~"
            iconBg: "#6b7280"
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
            splits: root.hcfg.splits === true
            sensitivity: (root.hcfg.sensitivity ?? 1.0)
            barColorCustom: root.hcfg.barColorCustom === true
            barColorFrom: root.hcfg.barColorFrom || "#e68e0d"
            barColorTo: root.hcfg.barColorTo || "#f59e0b"
            themeBottom: root.hostWidget ? (root.hostWidget.config.themeBottom || "#e68e0d") : "#e68e0d"
            themeTop: root.hostWidget ? (root.hostWidget.config.themeTop || "#f59e0b") : "#f59e0b"
          }
          MouseArea {
            anchors.fill: parent
            onDoubleClicked: { if (root.hostWidget) root.hostWidget.detach() }
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
        PanelSectionHeader { text: "OPTIONS" }

        // ---- Bars (spectrum) ----
        PanelSectionHeader { text: "BARS"; visible: root.isSpectrum }

        Row {
          visible: root.isSpectrum
          width: parent.width
          spacing: Style.space(14)

          Toggle {
            width: (parent.width - Style.space(14)) / 2
            label: "Peaks"
            description: "White peak-hold markers on each bar"
            checked: root.peaksOn
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("peaks", !checked)
          }

          Column {
            width: (parent.width - Style.space(14)) / 2
            spacing: Style.space(4)
            Text {
              text: "Peak fall speed"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              width: parent.width
              elide: Text.ElideRight
            }
            Text {
              text: "0 holds · 1 falls fast"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
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

        Row {
          visible: root.isSpectrum
          width: parent.width
          spacing: Style.space(14)

          Toggle {
            width: (parent.width - Style.space(14)) / 2
            label: "Spikes"
            description: "Dense thin flame spikes, no gaps (auto-enables Fire)"
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
            description: "Segmented bars with gaps, Winamp-style"
            checked: root.hcfg.splits === true
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("splits", !checked)
          }
        }

        Row {
          visible: root.isSpectrum
          width: parent.width
          spacing: Style.space(14)

          Toggle {
            width: (parent.width - Style.space(14)) / 2
            label: "Reflection"
            description: "Faded floor mirror below the bars"
            checked: root.hcfg.reflect === true
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("reflect", !checked)
          }

          Toggle {
            width: (parent.width - Style.space(14)) / 2
            label: "Artwork backdrop"
            description: "Album-cover behind bars (fallback: glow)"
            checked: root.hcfg.artwork !== false
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("artwork", !checked)
          }
        }

        // ---- Bar color (always visible; mini+preview+desktop in sync) ----
        PanelSectionHeader { text: "BAR COLOR" }

        Row {
          width: parent.width
          spacing: Style.space(14)

          Toggle {
            width: (parent.width - Style.space(14)) / 2
            label: "Custom colors"
            description: "Off = theme dominant colors"
            checked: root.hcfg.barColorCustom === true
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("bar_color_custom", !checked)
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
        Text {
          text: "Theme (default): theme dominant colors. Custom: your From → To gradient on mini, preview, desktop + wave. Mini Mono overrides this on the mini only."
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          width: parent.width
          wrapMode: Text.WordWrap
        }

        // ---- Oscilloscope-only ----
        PanelSectionHeader { text: "OSCILLOSCOPE"; visible: root.isScope }
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.isScope
          Text {
            text: "Waveform on mini, preview and desktop. Follows Bar color and Sensitivity."
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            width: parent.width
            wrapMode: Text.WordWrap
          }
          Text {
            text: "Line thickness"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            width: parent.width
          }
          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: 1; maximum: 5; step: 0.5
            value: (root.hcfg.scopeThickness ?? 2)
            onReleased: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption("scope_thickness", Math.round(v * 2) / 2) }
          }
        }

        // ---- Common (all modes) ----
        PanelSectionHeader { text: "COMMON" }
        Row {
          width: parent.width
          spacing: Style.space(14)

          Toggle {
            width: (parent.width - Style.space(14)) / 2
            label: "GPU renderer"
            description: "Desktop GPU shader (auto CPU fallback)"
            checked: root.hcfg.gpu !== false
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("gpu", !checked)
          }

          Toggle {
            width: (parent.width - Style.space(14)) / 2
            label: "Fire"
            description: "Flame gradient: bars, wash + wave"
            checked: root.hcfg.fire === true
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("fire", !checked)
          }
        }

        Toggle {
          width: parent.width
          label: "Linear fall"
          description: "Winamp-style instant rise, fixed-rate drop (restarts engine)"
          checked: root.hcfg.linearFall === true
          onClicked: if (root.hostWidget) root.hostWidget.writeEngineOption("linear_fall", !checked)
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          Text {
            text: "Sensitivity"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            width: parent.width
            elide: Text.ElideRight
          }
          Text {
            text: "Overall response (affects all viz)"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
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

        PanelSeparator { }

        // ---- Mini-only: Mono (waybar readability override) ----
        Rectangle {
          width: parent.width
          height: miniCol.implicitHeight + Style.space(16)
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(1,1,1,0.15)
          radius: Style.cornerRadius

          Column {
            id: miniCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(4)

            Text {
              text: "MINI ONLY"
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            }

            Toggle {
              width: parent.width
              label: "Mono (mini)"
              description: "B&W mini bars: black on light, white on dark (overrides Bar color)"
              checked: root.hcfg.mono === true
              onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("mono", !checked)
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
    property string iconText: ""
    property string iconBg: "#e68e0d"
    property bool selected: false
    signal cardClicked()

    width: (parent ? (parent.width - Style.space(8)) / 2 : 200)
    height: 66

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      border.width: 1
      border.color: card.selected ? Color.accent : Qt.rgba(1,1,1,0.08)
      color: card.selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14) : Color.popups.background

      Rectangle {
        width: 32
        height: 32
        radius: 7
        color: card.iconBg
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.space(6)

        Text {
          anchors.fill: parent
          text: card.iconText
          font.pixelSize: 14
          font.bold: true
          color: "#1b1b24"
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(6)
        text: card.labelText
        font.family: Style.font.family
        font.pixelSize: 12
        font.bold: true
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
