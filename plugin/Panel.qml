import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omaviz settings panel: PREVIEW + live OPTIONS + SOURCE.
// OPTIONS (Peaks / fall speed / Spikes / Fire) write through
// BarWidget.writeVizOption(), which updates disk + bar config immediately —
// mini, preview and the open desktop window all reflect changes at once.
// Detach lives on mini/preview double-click; the desktop window closes via ×.
//
// Bar-widget contract (verified against live BarWidget.qml):
//   injectPanel() sets:  t.bar, t.anchorItem, t.hostWidget, t.settings
//   the widget reads:    panelLoader.item.opened / open() / close() / toggle()
//
// We build on the shared `Panel` base (qs.Ui/Panel.qml) which owns the
// PanelController show/hide lifecycle, so opened/open/close/toggle resolve to
// the controller's open state — exactly what BarWidget.qml expects. The
// KeyboardPanel renders the popup surface (anchorItem + owner + open: root.opened).
// manageIpc is false so the panel does NOT register a second IpcHandler for the
// same target (BarWidget already owns it).
//
// Left-click on the bar button -> root.toggle() -> controller show/hide.
// Everything here is GPU-free: the panel never launches a window. The preview
// uses the Canvas-2D VisualCanvas (not the GL ShaderEffect) so it is safe to
// load inside the bar process.

Panel {
  id: root
  moduleName: "org.omaviz.visualizer"
  ipcTarget: "org.omaviz.visualizer"
  manageIpc: false

  // Config alias: live bar config once injected, sane defaults before.
  // Kills the 14x `hostWidget ? ... : default` guard repetition below.
  property var hcfg: root.hostWidget ? root.hostWidget.config : Model.defaultConfig()

  // ---- Injected by BarWidget.injectPanel() ----
  property var anchorItem: null
  property var hostWidget: null
  // `bar` and `settings` are provided by the Panel base and overwritten by
  // injectPanel(); declared here so the base binding does not error pre-injection.
  // NOTE (ADR-0008): the panel is read-only. There is no config buffer, no
  // commit()/readCfg()/reloadCfg() — the preview follows the live feed and
  // the footer is a SOURCE readout. All config reads live on BarWidget/Desktop.

  // ---- Popup lifecycle ----
  // IMPORTANT: do NOT override opened/open/close/toggle here. The `Panel`
  // base (qs.Ui/Panel.qml) owns a PanelController and drives the popup surface
  // through it: `opened` === panelController.open, and open()/close()/toggle()
  // call panelController.show()/hide(). The KeyboardPanel below binds its
  // `open` to `root.opened` (= panelController.open), so the show path is:
  //   BarWidget.toggle() -> panelLoader.item.toggle() -> Panel base toggle()
  //     -> panelController.show() -> panelController.open=true -> KeyboardPanel
  //        shows.
  // The earlier (broken) version overrode these to set panel.open directly,
  // which never invoked panelController.show(), so the panel never appeared.

  // ---- Live Bars preview (Canvas-2D, GPU-free, locked to Bars) ----
  // ADR-0008: no viz/style selector feeds it. The preview follows the live
  // feed (Model.spectrumData) and always renders Bars in the theme gradient.

  // ---- Source (read-only, from the engine's stdout) ----
  readonly property string sourceLabelText:
    Model.sourceLabel(Model.spectrumData.source || "")

  // surface
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    // Extra breathing room around the content (base default is
    // Style.spacing.popupPadding; we widen it for this panel).
    padding: Math.round(Style.spacing.popupPadding * 2)
    focusTarget: keyCatcher
    // Fixed size captured once at open — re-fitting on every control change
    // made the dialog jump/jitter when toggles altered implicit sizes.
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
      contentWidth: width          // vertical movement only — no horizontal
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      // Only interactive when content genuinely overflows — otherwise the
      // Flickable would eat drag gestures meant for sliders.
      interactive: contentHeight > height

      Column {
        id: column
        // Fill the padded viewport exactly like the shell's own panels
        // (kishan.clock): the KeyboardPanel's contentHolder already applies
        // the card's default padding, so NO extra x-offset or width fudge here.
        width: parent.width
        spacing: Style.space(10)

        // Helper: label at natural width, control takes ALL remaining space.
        // (Replaces the old `parent.width - Style.space(110)` hardcodes that
        // mis-sized controls and clipped their right edge.)
        component LabeledRow: Row {
          default property alias controlItem: holder.data
          property string label: ""
          width: parent ? parent.width : 0
          spacing: Style.space(10)
          Text {
            text: parent.label
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          Item {
            id: holder
            height: parent.height
            width: parent.width - (parent.children[0].implicitWidth + parent.spacing)
          }
        }

        // ---- Live preview ----
        PanelSectionHeader { text: "PREVIEW" }
        Rectangle {
          width: parent.width; height: Style.space(60)
          color: Color.popups.background
          radius: Style.cornerRadius
          border.width: 1; border.color: Qt.rgba(1,1,1,0.08)
          VisualCanvas {
            id: previewViz
            anchors.fill: parent; anchors.margins: Style.space(6)
            // Event-driven: bound straight to the bar's reactive spectrum
            // properties — no poll timer (the old 33ms timer added up to a
            // frame of display lag plus 30 wakeups/sec for nothing).
            bands: root.hostWidget ? root.hostWidget.spectrumBands : []
            silent: root.hostWidget ? root.hostWidget.spectrumSilent : true
            wave: root.hostWidget ? root.hostWidget.spectrumWave : []
            visual: root.hostWidget && root.hostWidget.config.scope === true ? "Oscilloscope" : "Bars"
            immersive: root.hcfg.immersive === true
            dots: root.hcfg.dots !== false
            reflect: root.hcfg.reflect === true
            scopeLineWidth: (root.hcfg.scopeThickness ?? 2)
            colorSync: false
            barCount: 64
                gapPx: root.hostWidget ? Math.min(6, Math.max(0, root.hostWidget.barGap)) : 1
            minBarHeight: 0
            // Live from bar config — settings below reflect immediately.
            peaks: root.hcfg.peaks !== false
            peakFalloff: (root.hcfg.peakFalloff ?? 0.5)
            spikes: root.hcfg.spikes === true
            fire: root.hcfg.fire === true
            splits: root.hcfg.splits === true
            sensitivity: (root.hcfg.sensitivity ?? 1.0)
            themeBottom: root.hostWidget ? (root.hostWidget.config.colorSync === true ? Qt.darker(Color.accent, 1.3) : (root.hostWidget.config.themeBottom || "#e68e0d")) : "#e68e0d"
            themeTop: root.hostWidget ? (root.hostWidget.config.colorSync === true ? Color.accent : (root.hostWidget.config.themeTop || "#f59e0b")) : "#f59e0b"
          }
          // Double-click on preview opens desktop window
          MouseArea {
            anchors.fill: parent
            onDoubleClicked: { root.hostWidget.detach() }
          }
        }
        Text {
          text: "Double-click preview to open full-screen visualization"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6)
          font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
          width: parent.width
          horizontalAlignment: Text.AlignLeft
        }
        // (VisualCanvas is a plain Canvas — properties bound inline above.)

        PanelSeparator { }

        // ---- Options (live-wired: writes go through BarWidget, which
        // updates disk + its own config immediately, so mini, preview
        // and the open desktop window all reflect the change at once)
        PanelSectionHeader { text: "OPTIONS" }
        // Mode selector + per-mode sections. Scope mode renders the
        // waveform on mini, preview and desktop alike.
        Dropdown {
          width: parent.width
          label: "Mode"
          options: [{ value: "spectrum", label: "Spectrum" }, { value: "scope", label: "Oscilloscope" }, { value: "immersive", label: "Immersive" }]
          value: panelOpts.mode
          onChanged: function(v) { if (root.hostWidget) root.hostWidget.writeVizOptions("scope", v === "scope", "immersive", v === "immersive") }
        }
        Column {
          id: panelOpts
          width: parent.width
          spacing: Style.space(10)
          property string mode: root.hcfg.immersive === true ? "immersive" : (root.hcfg.scope === true ? "scope" : "spectrum")
          property bool isScope: panelOpts.mode === "scope"
          property bool spikesOn: root.hcfg.spikes === true

          // ---- Spectrum-only ----
          PanelSectionHeader { text: "SPECTRUM"; visible: panelOpts.mode === "spectrum" }
          Toggle {
            visible: panelOpts.mode === "spectrum"
            id: peaksTgl
            width: parent.width
            label: "Peaks"
            description: "White peak-hold markers on each bar"
            checked: root.hcfg.peaks !== false
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("peaks", !checked)
          }
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: panelOpts.mode === "spectrum" && peaksTgl.checked
            Text {
              text: "Peak fall speed (0 holds, 1 falls fast)"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
              font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
              width: parent.width
            }
            PanelSlider {
              id: fallSlider
              width: parent.width
              bar: root.bar
              minimum: 0; maximum: 1; step: 0.05
              value: (root.hcfg.peakFalloff ?? 0.5)
              onReleased: function(v) { if (root.hostWidget) root.hostWidget.writeVizOption("peak_falloff", Math.round(v * 20) / 20) }
            }
          }
          Toggle {
            visible: panelOpts.mode === "spectrum"
            width: parent.width
            label: "Spikes"
            description: "Dense thin flame spikes, no gaps (auto-enables Fire)"
            checked: panelOpts.spikesOn
            onClicked: {
              if (!root.hostWidget) return
              var v = !checked
              root.hostWidget.writeVizOptions("spikes", v, "fire", v)
            }
          }
          Toggle {
            // Auto-managed by Spikes — hidden while spikes own it.
            visible: panelOpts.mode === "spectrum" && !panelOpts.spikesOn
            width: parent.width
            label: "Fire"
            description: "Red flame gradient from the base"
            checked: root.hcfg.fire === true
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("fire", !checked)
          }
          Toggle {
            visible: panelOpts.mode === "spectrum"
            width: parent.width
            label: "Stacks"
            description: "Segmented bars with gaps, Winamp-style (preview/desktop)"
            checked: root.hcfg.splits === true
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("splits", !checked)
          }
          Toggle {
            visible: panelOpts.mode === "spectrum"
            width: parent.width
            label: "Linear fall"
            description: "Winamp-style instant rise, fixed-rate drop (restarts engine)"
            checked: root.hcfg.linearFall === true
            onClicked: if (root.hostWidget) root.hostWidget.writeEngineOption("linear_fall", !checked)
          }
          Toggle {
            visible: panelOpts.mode === "spectrum"
            width: parent.width
            label: "Mono"
            description: "B&W mini bars: black on light themes, white on dark (overrides Fire)"
            checked: root.hcfg.mono === true
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("mono", !checked)
          }

          // ---- Oscilloscope-only ----
          PanelSectionHeader { text: "OSCILLOSCOPE"; visible: panelOpts.isScope }
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: panelOpts.isScope
            Text {
              text: "Waveform on mini, preview and desktop. Follows Fire color and Sensitivity."
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
              font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
              width: parent.width
              wrapMode: Text.WordWrap
            }
            Text {
              text: "Line thickness"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
              font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
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

          // ---- Immersive-only ----
          PanelSectionHeader { text: "IMMERSIVE"; visible: panelOpts.mode === "immersive" }
          Text {
            visible: panelOpts.mode === "immersive"
            text: "Artwork wash + quiet white bars on preview/desktop (mini: wash only, no art)."
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
            width: parent.width
            wrapMode: Text.WordWrap
          }
          Toggle {
            visible: panelOpts.mode === "immersive"
            width: parent.width
            label: "Artwork"
            description: "Album-art backdrop when available (fallback: reactive glow)"
            checked: root.hcfg.artwork !== false
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("artwork", !checked)
          }

          // ---- Common (all modes) ----
          PanelSectionHeader { text: "COMMON" }
          Toggle {
            width: parent.width
            label: "Dots"
            description: "Dotted skin backdrop behind the bars"
            checked: root.hcfg.dots !== false
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("dots", !checked)
          }
          Toggle {
            width: parent.width
            label: "Reflection"
            description: "Faded floor mirror below the bars (preview/desktop)"
            checked: root.hcfg.reflect === true
            onClicked: if (root.hostWidget) root.hostWidget.writeVizOption("reflect", !checked)
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
            font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: root.sourceLabelText + " · default sink"
            color: Color.accent
            font.family: Style.font.family; font.pixelSize: Style.font.body
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

}
