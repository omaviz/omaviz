import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// Shared options form: dependency-free (no qs.*) so it loads both in the
// bar settings Panel and in the standalone desktop window's hover drawer.
// Single source of truth for every viz option — do NOT duplicate these
// controls elsewhere.
//
// Contract:
//   cfg: live config object (Panel: hcfg alias, Desktop: win.vizConfig)
//   signals carry JS values; the host converts + writes (BarWidget.vizVal
//   and Desktop's local equivalent handle bool->"true"/"false").
Column {
  id: form
  spacing: 10

  property var cfg: Model.defaultConfig()
  property color fg: "#e8e8f0"
  property color muted: "#9a9ab0"
  property color accent: "#f59e0b"

  signal vizOption(string key, var value)
  signal vizOptions(string key1, var value1, string key2, var value2)
  signal engineOption(string key, var value)

  readonly property bool isScope: form.cfg.scope === true
  readonly property bool spikesOn: form.cfg.spikes === true
  readonly property bool peaksOn: form.cfg.peaks !== false

  // ---- self-drawn controls (no shell theme dependency) ----
  component OFHeader: Text {
    property bool show: true
    visible: show
    color: form.muted
    font.pixelSize: 11
    font.letterSpacing: 1
  }
  component OFToggle: Row {
    property string label: ""
    property string description: ""
    property bool checked: false
    signal toggled()
    width: parent ? parent.width : 200
    spacing: 8
    Rectangle {
      id: track
      width: 34; height: 19; radius: 9
      anchors.verticalCenter: parent.verticalCenter
      color: parent.checked ? form.accent : "#3a3a48"
      Rectangle {
        width: 13; height: 13; radius: 6
        x: parent.parent.checked ? 18 : 3
        anchors.verticalCenter: parent.verticalCenter
        color: "#ffffff"
        Behavior on x { NumberAnimation { duration: 120 } }
      }
      MouseArea {
        anchors.fill: parent
        onClicked: { var r = parent.parent; r.toggled() }
      }
    }
    Column {
      width: parent.width - 42
      anchors.verticalCenter: parent.verticalCenter
      Text { text: parent.parent.label; color: form.fg; font.pixelSize: 12; width: parent.width }
      Text {
        text: parent.parent.description; color: form.muted; font.pixelSize: 11
        width: parent.width; wrapMode: Text.WordWrap; visible: parent.parent.description !== ""
      }
    }
    MouseArea {
      // Whole row clickable (covers the label area too).
      x: 42; width: parent.width - 42; height: parent.height
      onClicked: parent.toggled()
    }
  }
  component OFSlider: Column {
    property string label: ""
    property real from: 0
    property real to: 1
    property real step: 0.05
    property real value: 0.5
    signal settled(real v)
    width: parent ? parent.width : 200
    spacing: 4
    Text { text: parent.label; color: form.muted; font.pixelSize: 11; width: parent.width }
    Slider {
      width: parent.width
      from: parent.from; to: parent.to; stepSize: parent.step
      value: parent.value
      onMoved: parent.value = value
      onPressedChanged: if (!pressed) parent.settled(value)
      background: Rectangle {
        x: parent.leftPadding; y: parent.topPadding + parent.availableHeight / 2 - 2
        width: parent.availableWidth; height: 4; radius: 2; color: "#3a3a48"
        Rectangle { width: parent.parent.visualPosition * parent.width; height: 4; radius: 2; color: form.accent }
      }
      handle: Rectangle {
        x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
        y: parent.topPadding + parent.availableHeight / 2 - height / 2
        width: 14; height: 14; radius: 7; color: "#ffffff"
      }
    }
  }

  // ---- Mode ----
  OFHeader { text: "MODE" }
  ComboBox {
    width: parent.width
    model: ["Spectrum", "Oscilloscope"]
    currentIndex: form.isScope ? 1 : 0
    onActivated: function(i) { form.vizOption("scope", i === 1) }
    background: Rectangle { color: "#1c1c26"; radius: 4; border.width: 1; border.color: "#3a3a48" }
    contentItem: Text {
      text: parent.model[parent.currentIndex]; color: form.fg; font.pixelSize: 12
      verticalAlignment: Text.AlignVCenter; leftPadding: 8
    }
  }

  // ---- Spectrum-only ----
  OFHeader { text: "SPECTRUM"; show: !form.isScope }
  OFToggle {
    visible: !form.isScope
    label: "Peaks"; description: "White peak-hold markers on each bar"
    checked: form.peaksOn
    onToggled: form.vizOption("peaks", !checked)
  }
  OFSlider {
    visible: !form.isScope && form.peaksOn
    label: "Peak fall speed (0 holds, 1 falls fast)"
    from: 0; to: 1; step: 0.05; value: (form.cfg.peakFalloff ?? 0.5)
    onSettled: function(v) { form.vizOption("peak_falloff", Math.round(v * 20) / 20) }
  }
  OFToggle {
    visible: !form.isScope
    label: "Spikes"; description: "Dense thin flame spikes, no gaps (auto-enables Fire)"
    checked: form.spikesOn
    onToggled: form.vizOptions("spikes", !checked, "fire", !checked)
  }
  OFToggle {
    // Auto-managed by Spikes — hidden while spikes own it.
    visible: !form.isScope && !form.spikesOn
    label: "Fire"; description: "Red flame gradient from the base"
    checked: form.cfg.fire === true
    onToggled: form.vizOption("fire", !checked)
  }
  OFToggle {
    visible: !form.isScope
    label: "Stacks"; description: "Segmented bars with gaps, Winamp-style"
    checked: form.cfg.splits === true
    onToggled: form.vizOption("splits", !checked)
  }
  OFToggle {
    visible: !form.isScope
    label: "Linear fall"; description: "Winamp-style instant rise, fixed-rate drop (restarts engine)"
    checked: form.cfg.linearFall === true
    onToggled: form.engineOption("linear_fall", !checked)
  }
  OFToggle {
    visible: !form.isScope
    label: "Mono"; description: "B&W mini bars: black on light themes, white on dark (overrides Fire)"
    checked: form.cfg.mono === true
    onToggled: form.vizOption("mono", !checked)
  }

  // ---- Oscilloscope-only ----
  OFHeader { text: "OSCILLOSCOPE"; show: form.isScope }
  Text {
    visible: form.isScope
    text: "Waveform on mini, preview and desktop. Follows Fire color and Sensitivity."
    color: form.muted; font.pixelSize: 11; width: parent.width; wrapMode: Text.WordWrap
  }
  OFSlider {
    visible: form.isScope
    label: "Line thickness"
    from: 1; to: 5; step: 0.5; value: (form.cfg.scopeThickness ?? 2)
    onSettled: function(v) { form.vizOption("scope_thickness", Math.round(v * 2) / 2) }
  }

  // ---- Common (both modes) ----
  OFHeader { text: "COMMON" }
  OFToggle {
    label: "Dots"; description: "Dotted skin backdrop behind the bars"
    checked: form.cfg.dots !== false
    onToggled: form.vizOption("dots", !checked)
  }
  OFToggle {
    label: "Reflection"; description: "Faded floor mirror below the bars"
    checked: form.cfg.reflect === true
    onToggled: form.vizOption("reflect", !checked)
  }
}
