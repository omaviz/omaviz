import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omaviz settings panel (bars-minimum ADR-0008: PREVIEW + SOURCE only).
// The panel writes NOTHING — no viz/fire/detach/density controls. Detach
// lives on BarWidget right-click; the desktop window closes via its own ×.
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
            property var _liveBands: []
            property bool _liveSilent: true
            Timer {
              interval: 33; repeat: true; running: true
              onTriggered: {
                var nb = Model.spectrumData.bands
                previewViz._liveBands = nb
                previewViz._liveSilent = Model.spectrumData.silent
              }
            }
            bands: previewViz._liveBands
            silent: previewViz._liveSilent
            visual: "Bars"
            style: "Classic"
            colorSync: false
            barCount: 64
            colourScheme: 0
            gapPx: 1
            minBarHeight: 0
            peaks: true
            peakFalloff: 0.5
          }
          // Double-click on preview opens desktop window
          MouseArea {
            anchors.fill: parent
            onDoubleClicked: { root.hostWidget.detach() }
          }
        }
        // (VisualCanvas is a plain Canvas — properties bound inline above.)

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
