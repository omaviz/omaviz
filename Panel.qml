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
  property string pluginVersion: ""
  FileView {
    path: Qt.resolvedUrl("manifest.json")
    onLoaded: {
      try { root.pluginVersion = JSON.parse(text()).version || "" }
      catch (error) { console.warn("omaviz: cannot read plugin version", error) }
    }
  }

  // Panel foreground palette — the panel is hosted by the bar (bar.foreground)
  // or runs detached (shell Color.foreground). Defined ONCE, used ~18 times.
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color fgMuted: Qt.darker(fg, 1.4)
  readonly property color fgFaint: Qt.darker(fg, 1.6)

  readonly property string sourceLabelText:
    Store.sourceLabel(root.hostWidget ? root.hostWidget.spectrumSource : Store.spectrumData.source || "")

  readonly property bool isScope: root.hcfg.visual === "Waves"
  readonly property bool isSpectrum: root.hcfg.visual === "Bars"
  readonly property bool isWaves: root.hcfg.visual === "Waves"
  readonly property bool isStrings: root.hcfg.visual === "Strings"
  readonly property bool isSiri: root.hcfg.visual === "Siri"
  readonly property bool isDecorative: isSiri || isStrings

  // ---- Derived option state (one concept each) ----
  readonly property bool peaksOn: root.hcfg.peaks !== false
  readonly property bool spikesOn: root.hcfg.spikes === true
  readonly property bool stacksOn: root.hcfg.stacks === true
  readonly property bool artworkOn: root.isSpectrum && root.hcfg.artworkColors === true
  readonly property bool fireOn: !root.artworkOn && !root.isDecorative && root.hcfg.fire === true
  readonly property bool customOn: !root.artworkOn && root.hcfg.barColorCustom === true
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
  function exitPlugin() {
    if (root.hostWidget && root.hostWidget.requestExit) root.hostWidget.requestExit()
    root.close()
  }

  function revealControl(item) {
    if (!item.activeFocus) return
    var p = item.mapToItem(scroll.contentItem, 0, 0)
    var target = scroll.contentY
    if (p.y < target) target = p.y
    else if (p.y + item.height > target + scroll.height) target = p.y + item.height - scroll.height
    scroll.contentY = Math.max(0, Math.min(target, Math.max(0, scroll.contentHeight - scroll.height)))
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
    focusTarget: onOffSwitch
    property bool _sizeLocked: false
    property int _frozenH: 0
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: root.vizEnabled && _sizeLocked ? _frozenH : panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: -panel.padding
      radius: Style.cornerRadius
      color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
    }

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      Keys.onEscapePressed: root.close()
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: column
        width: parent.width
        spacing: Style.space(8)

        // ---- Plugin identity and ON/OFF toggle (always visible) ----
        Item {
          width: parent.width
          height: Style.space(30)
          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              text: "OMAVIZ"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: (root.pluginVersion ? "v" + root.pluginVersion + "  ·  " : "") + "Audio visualizer"
              color: root.fgMuted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
          ToggleSwitch {
            id: onOffSwitch
            activeFocusOnTab: true
            hasCursor: activeFocus
            cursorRing: activeFocus
            Accessible.role: Accessible.CheckBox
            Accessible.name: "Enable visualizer"
            Accessible.checked: checked
            Accessible.onToggleAction: root.setVizEnabled(!checked)
            Keys.onSpacePressed: root.setVizEnabled(!checked)
            Keys.onReturnPressed: root.setVizEnabled(!checked)
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
        PanelSeparator { }
        Item {
          width: parent.width
          height: Style.space(16)
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - exitText.width - Style.space(8)
            text: "SOURCE  " + root.sourceLabelText
            elide: Text.ElideRight
            color: root.fgMuted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          ActionText {
            id: exitText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Exit"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            onActivated: root.exitPlugin()
          }
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
      //  VISUALIZATIONS — shared GPU modes
      // ============================================================
      PanelSectionHeader { text: "VISUALIZATIONS" }

      ModeSelect {
        width: parent.width
        Accessible.name: "Visualization family"
        model: ["Spectrum", "Waveforms"]
        currentIndex: root.isSpectrum ? 0 : 1
        onActivated: function(index) {
          if (root.hostWidget) root.hostWidget.writeVizOptions("visual", index === 0 ? "Bars" : "Waves", "scope", index !== 0)
        }
      }
      ModeSelect {
        width: parent.width
        visible: !root.isSpectrum
        Accessible.name: "Waveform style"
        model: ["Waves · audio trace", "Strings · vibrating strands", "Siri · luminous ribbons"]
        currentIndex: root.isSiri ? 2 : root.isStrings ? 1 : 0
        onActivated: function(index) {
          if (root.hostWidget) root.hostWidget.writeVizOptions("visual", ["Waves", "Strings", "Siri"][index], "scope", index === 0)
        }
      }

      // Cache static settings separately from the animated preview. Qt keeps
      // native-resolution text/controls in one texture until a setting changes.
      Column {
        width: parent.width
        spacing: Style.space(8)
        layer.enabled: true

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

        // Everyday Spectrum controls; fall behavior lives in Fine tuning.
        Row {
          width: parent.width
          spacing: Style.space(14)

          Toggle {
            onActiveFocusChanged: root.revealControl(this)
            Accessible.role: Accessible.CheckBox
            Accessible.name: label
            Accessible.checked: checked
            Accessible.onToggleAction: clicked()
            width: (parent.width - Style.space(14)) / 2
            label: "Peaks"
            description: "Peak-hold markers"
            checked: root.peaksOn
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("peaks", !checked)
          }
          Toggle {
            onActiveFocusChanged: root.revealControl(this)
            Accessible.role: Accessible.CheckBox
            Accessible.name: label
            Accessible.checked: checked
            Accessible.onToggleAction: clicked()
            width: (parent.width - Style.space(14)) / 2
            label: "Reflection"
            description: "Floor mirror"
            checked: root.hcfg.reflect === true
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("reflect", !checked)
          }

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
            width: (modeRow.width - Style.space(6) * (root.isSpectrum ? 3 : root.isDecorative ? 1 : 2)) / (root.isSpectrum ? 4 : root.isDecorative ? 2 : 3)
            chipLabel: root.isStrings ? "Original" : root.isSiri ? "Prism" : "Theme"
            selected: !root.artworkOn && !root.fireOn && !root.customOn
            onChipClicked: if (root.hostWidget) root.hostWidget.setColorMode("Theme")
          }
          Chip {
            width: (modeRow.width - Style.space(6) * (root.isSpectrum ? 3 : root.isDecorative ? 1 : 2)) / (root.isSpectrum ? 4 : root.isDecorative ? 2 : 3)
            chipLabel: "Custom"
            selected: !root.fireOn && root.customOn
            onChipClicked: if (root.hostWidget) root.hostWidget.setColorMode("Custom")
          }
          Chip {
            width: (modeRow.width - Style.space(18)) / 4
            visible: root.isSpectrum
            chipLabel: "Artwork"
            selected: root.artworkOn
            onChipClicked: if (root.hostWidget) root.hostWidget.setColorMode("Artwork")
          }
          Chip {
            width: (modeRow.width - Style.space(6) * (root.isSpectrum ? 3 : root.isDecorative ? 1 : 2)) / (root.isSpectrum ? 4 : root.isDecorative ? 2 : 3)
            visible: !root.isDecorative
            chipLabel: "Flame"
            selected: root.fireOn
            onChipClicked: if (root.hostWidget) root.hostWidget.setColorMode("Flame")
          }
        }
      }

      Text {
        width: parent.width
        visible: root.artworkOn
        text: root.hostWidget && root.hostWidget.artworkPalette.length >= 3
          ? "Colors follow the current cover. Desktop adds a tinted atmosphere."
          : "Waiting for cover artwork — using theme colors."
        color: root.fgMuted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      BorderSurface {
        width: parent.width
        visible: root.tonesActive
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

            Text {
              text: root.fireOn ? "Flame tones" : root.isStrings ? "String colors" : "Custom tones"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              width: parent.width
              elide: Text.ElideRight
            }
            Text {
              text: root.fireOn ? "From (base) · To (flame tip)" : "Start · End — enter any hex color"
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
                accessibleLabel: "Start color"
                value: root.fireOn ? root.hcfg.fireColorFrom : root.hcfg.barColorFrom
                onAccept: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption(root.fireOn ? "fire_color_from" : "bar_color_from", v) }
              }
              HexField {
                width: (parent.width - Style.space(8)) / 2
                accessibleLabel: "End color"
                value: root.fireOn ? root.hcfg.fireColorTo : root.hcfg.barColorTo
                onAccept: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption(root.fireOn ? "fire_color_to" : "bar_color_to", v) }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.customOn && !root.fireOn
            Chip {
              width: parent.width
              chipLabel: root.hcfg.barColorMiddleEnabled ? "− Remove middle color" : "+ Add middle color"
              selected: root.hcfg.barColorMiddleEnabled === true
              onChipClicked: if (root.hostWidget) root.hostWidget.writeVizOption("bar_color_middle_enabled", !root.hcfg.barColorMiddleEnabled)
            }
            HexField {
              width: parent.width
              visible: root.hcfg.barColorMiddleEnabled === true
              accessibleLabel: "Middle color"
              value: root.hcfg.barColorMiddle || "#a855f7"
              onAccept: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption("bar_color_middle", v) }
            }
          }

          // Gradient direction: bottom->top (default) or left->right.
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.isSpectrum && root.customOn && !root.fireOn
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
              PaletteSwatch {
                accessibleLabel: "Palette " + modelData[0] + " to " + modelData[1]
                width: (presetRow.width - Style.space(root.isDecorative ? 48 : 54)) / (root.isDecorative ? 9 : 10)
                height: 22
                radius: 5
                gradient: Gradient {
                  GradientStop { position: 0.0; color: modelData[0] }
                  GradientStop { position: 1.0; color: modelData[1] }
                }
                border.width: (!root.fireOn && root.customOn && root.hcfg.barColorFrom === modelData[0] && root.hcfg.barColorTo === modelData[1] && !root.hcfg.barColorMiddleEnabled) ? 2 : 0
                border.color: Color.accent
                onActivated: if (root.hostWidget) root.hostWidget.writeVizOptions3("fire", false, "bar_color_custom", true, "bar_color_from", modelData[0], "bar_color_to", modelData[1], "bar_color_middle_enabled", false)
              }
            }
            PaletteSwatch {
              accessibleLabel: "Peacock palette"
              width: (presetRow.width - Style.space(root.isDecorative ? 48 : 54)) / (root.isDecorative ? 9 : 10)
              height: 22
              radius: 5
              gradient: Gradient {
                GradientStop { position: 0; color: "#008c95" }
                GradientStop { position: 0.5; color: "#663cc8" }
                GradientStop { position: 1; color: "#c5c94b" }
              }
              border.width: root.customOn && root.hcfg.barColorMiddleEnabled && root.hcfg.barColorFrom === "#008c95" && root.hcfg.barColorMiddle === "#663cc8" && root.hcfg.barColorTo === "#c5c94b" ? 2 : 0
              border.color: Color.accent
              onActivated: if (root.hostWidget) root.hostWidget.writeVizMap({
                  fire: false, artwork_colors: false, bar_color_custom: true,
                  bar_color_from: "#008c95", bar_color_middle: "#663cc8",
                  bar_color_to: "#c5c94b", bar_color_middle_enabled: true
                })
            }
            // Fire swatch — selecting it switches to Flame colour mode.
            PaletteSwatch {
              accessibleLabel: "Flame palette"
              visible: !root.isDecorative
              width: (presetRow.width - Style.space(54)) / 10
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
              onActivated: if (root.hostWidget) root.hostWidget.setColorMode("Flame")
            }
          }
          Text {
            text: "Presets apply to mini, preview, and desktop."
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
          id: responseCard
          width: parent.width
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
            OptionSlider {
              width: parent.width
              bar: root.bar
              accessibleLabel: "Response"
              minimum: 0.5; maximum: 2; step: 0.1
              value: (root.hcfg.sensitivity ?? 1.0)
              onReleased: function(v) { if (root.hostWidget) root.hostWidget.writeAudioOption("sensitivity", Math.round(v * 10) / 10) }
            }
          }
        }

      }
      Text {
        visible: root.showAdvanced
        text: "Response scales bar reactivity and waveform amplitude with input gain."
        color: root.fgMuted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        width: parent.width
        wrapMode: Text.WordWrap
      }

      // ============================================================
      //  WAVEFORMS — shared line thickness
      // ============================================================

      // ============================================================
      //  ADVANCED — collapsed; rarely-touched controls
      // ============================================================
      PanelSeparator { }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Text {
          text: "FINE TUNING"
          color: root.fgMuted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          topPadding: Math.ceil(Style.font.caption * 0.15)
          width: parent.width - advLink.width - parent.spacing
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
        }
        ActionText {
          id: advLink
          text: root.showAdvanced ? "Hide" : "Show"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
          onActivated: root.showAdvanced = !root.showAdvanced
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.showAdvanced
        BorderSurface {
          id: fallCard
          visible: root.isSpectrum && root.peaksOn
          width: parent.width
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
            OptionSlider {
              width: parent.width
              bar: root.bar
              enabled: root.peaksOn
              accessibleLabel: "Peak fall speed"
              minimum: 0; maximum: 1; step: 0.05
              value: (root.hcfg.peakFalloff ?? 0.1)
              onReleased: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption("peak_falloff", Math.round(v * 20) / 20) }
            }
          }
        }
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: !root.isSpectrum && !root.isSiri

          PanelSeparator { }
          PanelSectionHeader { text: "WAVEFORM" }
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
              OptionSlider {
                width: parent.width
                bar: root.bar
                accessibleLabel: "Line thickness"
                minimum: 1; maximum: 5; step: 0.5
                value: (root.hcfg.scopeThickness ?? 2)
                onReleased: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption("scope_thickness", Math.round(v * 2) / 2) }
              }
            }
          }
        }
        Toggle {
          onActiveFocusChanged: root.revealControl(this)
          Accessible.role: Accessible.CheckBox
          Accessible.name: label
          Accessible.checked: checked
          Accessible.onToggleAction: clicked()

          width: parent.width

          label: "Mono (mini only)"
          description: "B&W mini bars"
          checked: root.hcfg.mono === true
          onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("mono", !checked)
        }

        Row {
          visible: !root.isDecorative
          width: parent.width
          spacing: Style.space(14)

          Toggle {
            onActiveFocusChanged: root.revealControl(this)
            Accessible.role: Accessible.CheckBox
            Accessible.name: label
            Accessible.checked: checked
            Accessible.onToggleAction: clicked()
            width: (parent.width - Style.space(14)) / 2
            visible: root.isSpectrum
            label: "Linear fall"
            description: "Fixed-rate drop"
            checked: root.hcfg.linearFall === true
            onClicked: if (root.hostWidget) root.hostWidget.writeEngineOption("linear_fall", !checked)
          }

          Toggle {
            onActiveFocusChanged: root.revealControl(this)
            Accessible.role: Accessible.CheckBox
            Accessible.name: label
            Accessible.checked: checked
            Accessible.onToggleAction: clicked()
            width: (parent.width - Style.space(14)) / 2
            visible: !root.isDecorative
            label: "Dots"
            description: "Faint dot grid"
            checked: root.hcfg.dots !== false
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("dots", !checked)
          }
        }

        Row {
          visible: root.isSpectrum
          width: parent.width
          spacing: Style.space(14)

          Toggle {
            onActiveFocusChanged: root.revealControl(this)
            Accessible.role: Accessible.CheckBox
            Accessible.name: label
            Accessible.checked: checked
            Accessible.onToggleAction: clicked()
            width: parent.width
            label: "Artwork backdrop"
            description: "Immersive backdrop"
            checked: root.hcfg.artwork !== false
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("artwork", !checked)
          }
        }
      }

      } // cached settings

      // ============================================================
      //  PREVIEW — live canvas
      // ============================================================
      PanelSectionHeader { text: "PREVIEW" }

      Rectangle {
        width: parent.width
        height: Style.space(132)
        color: "#000000"
        radius: Style.cornerRadius
        border.width: 1
        border.color: Qt.rgba(1,1,1,0.08)

        DotsCanvas {
          anchors.fill: parent
          anchors.margins: Style.space(6)
          visible: root.hcfg.dots !== false && !root.isDecorative
        }
        VisualCanvas {
          id: previewViz
          anchors.fill: parent
          anchors.margins: Style.space(6)
          dots: false
          bands: root.hostWidget ? root.hostWidget.spectrumBands : []
          silent: root.hostWidget ? root.hostWidget.spectrumSilent : true
          wave: root.hostWidget ? root.hostWidget.spectrumWave : []
          visual: root.hcfg.visual || "Bars"
          wash: false
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
          artworkColors: root.artworkOn
          artworkPalette: root.hostWidget ? root.hostWidget.artworkPalette : []
          barColorCustom: root.customOn
          barColorFrom: root.hcfg.barColorFrom || "#e68e0d"
          barColorTo: root.hcfg.barColorTo || "#f59e0b"
          barColorMiddle: root.hcfg.barColorMiddle || "#a855f7"
          barColorMiddleEnabled: root.hcfg.barColorMiddleEnabled === true
          gradientDir: root.gradDir
          themeBottom: Qt.darker(Color.accent, 1.3)
          themeTop: Color.accent
        }
        Item {
          anchors.fill: parent
          activeFocusOnTab: true
          onActiveFocusChanged: root.revealControl(this)
          Accessible.role: Accessible.Button
          Accessible.name: "Open desktop visualizer"
          function activate() { if (root.hostWidget) root.hostWidget.detach() }
          Accessible.onPressAction: activate()
          Keys.onSpacePressed: activate()
          Keys.onReturnPressed: activate()
          Rectangle { anchors.fill: parent; color: "transparent"; border.width: parent.activeFocus ? 2 : 0; border.color: Color.accent }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.activate() }
        }
      }
      Text {
        text: "Click preview to open desktop visualizer"
        color: root.fgFaint
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        width: parent.width
        horizontalAlignment: Text.AlignLeft
      }

    }
  }

  // ---- Reusable components ----
  component ActionText: Text {
    id: actionText
    signal activated()
    activeFocusOnTab: true
    onActiveFocusChanged: root.revealControl(actionText)
    font.underline: activeFocus
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: activated()
    Keys.onSpacePressed: activated()
    Keys.onReturnPressed: activated()
    Keys.onEnterPressed: activated()
    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: actionText.activated() }
  }

  component PaletteSwatch: Rectangle {
    id: swatch
    property string accessibleLabel: "Color palette"
    signal activated()
    activeFocusOnTab: true
    onActiveFocusChanged: root.revealControl(swatch)
    Accessible.role: Accessible.Button
    Accessible.name: accessibleLabel
    Accessible.onPressAction: activated()
    Keys.onSpacePressed: activated()
    Keys.onReturnPressed: activated()
    ToolTip.visible: swatchPointer.containsMouse || activeFocus
    ToolTip.text: accessibleLabel
    Rectangle { anchors.fill: parent; anchors.margins: -2; radius: parent.radius + 2; color: "transparent"; border.width: parent.activeFocus ? 1 : 0; border.color: Color.accent }
    MouseArea { id: swatchPointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: swatch.activated() }
  }

  component OptionSlider: PanelSlider {
    id: optionSlider
    property string accessibleLabel: "Visualization setting"
    activeFocusOnTab: true
    onActiveFocusChanged: root.revealControl(optionSlider)
    Accessible.role: Accessible.Slider
    Accessible.name: accessibleLabel
    Accessible.description: String(value)
    function adjust(delta) {
      var next = Math.max(minimum, Math.min(maximum, Math.round((value + delta) / step) * step))
      released(next)
    }
    Keys.onLeftPressed: adjust(-step)
    Keys.onRightPressed: adjust(step)
    Keys.onDownPressed: adjust(-step)
    Keys.onUpPressed: adjust(step)
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Home) { released(minimum); event.accepted = true }
      else if (event.key === Qt.Key_End) { released(maximum); event.accepted = true }
    }
    Accessible.onIncreaseAction: adjust(step)
    Accessible.onDecreaseAction: adjust(-step)
    Rectangle { anchors.fill: parent; anchors.margins: -2; radius: 3; color: "transparent"; border.width: parent.activeFocus ? 1 : 0; border.color: Color.accent }
  }

  component ModeSelect: ComboBox {
    id: selector
    height: Style.space(38)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    Accessible.name: "Visualization style"
    onActiveFocusChanged: root.revealControl(selector)
    contentItem: Text {
      leftPadding: Style.space(12)
      rightPadding: Style.space(32)
      text: selector.displayText
      color: root.fg
      font: selector.font
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
    indicator: Text {
      x: selector.width - width - Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: "⌄"
      color: root.fg
    }
    background: Rectangle {
      radius: Style.cornerRadius
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
      border.width: 1
      border.color: selector.activeFocus ? Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.2)
    }
    delegate: ItemDelegate {
      required property int index
      required property var modelData
      width: selector.width
      text: modelData
      highlighted: selector.highlightedIndex === index
      contentItem: Text {
        text: parent.text
        color: root.fg
        font: selector.font
        elide: Text.ElideRight
      }
      background: Rectangle { color: parent.highlighted ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : Color.popups.background }
    }
    popup: Popup {
      y: selector.height + Style.space(4)
      width: selector.width
      padding: 1
      implicitHeight: Math.min(contentItem.implicitHeight + 2, Style.space(240))
      background: Rectangle { color: Color.popups.background; border.color: Color.accent; radius: Style.cornerRadius }
      contentItem: ListView {
        clip: true
        implicitHeight: contentHeight
        model: selector.popup.visible ? selector.delegateModel : null
        currentIndex: selector.highlightedIndex
        ScrollIndicator.vertical: ScrollIndicator { }
      }
    }
  }

  component Chip: Item {
    id: chip
    property string chipLabel: ""
    property bool selected: false
    signal chipClicked()

    height: 30
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: chipLabel
    Accessible.checkable: true
    Accessible.checked: selected
    onActiveFocusChanged: root.revealControl(chip)
    Accessible.onPressAction: chipClicked()
    Keys.onSpacePressed: chipClicked()
    Keys.onReturnPressed: chipClicked()
    Keys.onEnterPressed: chipClicked()

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      border.width: 1
      border.color: chip.selected || chip.activeFocus ? Color.accent : Qt.rgba(1,1,1,0.10)
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

    height: 30
    property string accessibleLabel: "Hex color"
    onValueChanged: if (!hexInput.activeFocus) hexInput.text = value

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
          activeFocusOnTab: true
          Accessible.name: hexField.accessibleLabel
          selectByMouse: true
          onActiveFocusChanged: { if (!activeFocus) hexField.submit(text); else root.revealControl(hexInput) }
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
