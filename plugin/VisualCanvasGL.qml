import QtQuick
import "glspectrum.js" as GLpack

// GPU visualization renderer (v7.1).
//
// QML ShaderEffect driven by a precompiled GLSL shader (visual.qsb, built by
// build.sh). Winamp-style Bars/Wave/Fire on the GPU.
//
// Data path: live `bands` -> packed to 32 floats + scalar controls -> painted
// into a visible 32x4 Canvas -> exposed as a ShaderEffectSource texture
// (u_tex). The shader reads spectrum from row 0 and the scalar controls from
// rows 1-2 (avoids Qt6 uniform-block upload pitfalls). No UBO is used.
//
// Contract (drop-in for VisualCanvas.qml):
//   bands, silent, visual, style, colorSync, colourScheme, barCount, monoColor

Item {
  id: root
  property var bands: []
  property bool silent: false
  property string visual: "Bars"
  property string style: "Classic"
  property bool colorSync: true   // detached window is colored by default
  property int barCount: 0
  property int colourScheme: 0
  property color monoColor: "#dce0eb"

  readonly property var packed: silent
    ? (function () { var z = []; for (var i = 0; i < 32; i++) z.push(0); return z })()
    : GLpack.packBands(bands, 32)
  readonly property real u_peak: GLpack.peakOf(packed)

  readonly property int   cVisual: (visual === "Wave") ? 1 : 0
  readonly property int   cStyle:  (style === "Fire" && visual !== "Wave") ? 1 : 0
  readonly property int   cColor:  colorSync ? 1 : 0
  readonly property int   cScheme: colourScheme
  property real u_time: 0
  NumberAnimation on u_time { running: true; loops: Animation.Infinite; from: 0; to: 1000; duration: 1000000 }

  // Visible 32x4 canvas; ShaderEffectSource renders it into a texture.
  // Row 0 = spectrum (R channel), Row 1 = scalar controls, Row 2 = peak/time.
  // visible:true REQUIRED (hidden from window via hideSource).
  Canvas {
    id: specCanvas
    width: 32; height: 4
    visible: true
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      // Row 0: spectrum magnitudes
      for (var i = 0; i < 32; i++) {
        var v = packed[i] || 0
        var g = Math.round(Math.min(1, Math.max(0, v)) * 255)
        ctx.fillStyle = "rgb(" + g + "," + g + "," + g + ")"
        ctx.fillRect(i, 0, 1, 1)
      }
      // Row 1: controls (R=visual G=style B=color), full width. Single fill so
      // no channel is overwritten. Scheme goes in row 2's B channel.
      ctx.fillStyle = "rgb(" + (cVisual*255) + "," + (cStyle*255) + "," + (cColor*255) + ")"
      ctx.fillRect(0, 1, 32, 1)
      // Row 2: peak + time + scheme, full width
      var pk = Math.round(Math.min(1, Math.max(0, u_peak)) * 255)
      var tm = Math.round(Math.min(1, Math.max(0, (u_time % 1000) / 1000)) * 255)
      var sc = Math.round(Math.min(1, Math.max(0, cScheme / 2.0)) * 255)
      ctx.fillStyle = "rgb(" + pk + "," + tm + "," + sc + ")"
      ctx.fillRect(0, 2, 32, 1)
    }
    Component.onCompleted: requestPaint()
  }
  Connections {
    target: root
    function onBandsChanged() { specCanvas.requestPaint() }
    function onSilentChanged() { specCanvas.requestPaint() }
    function onCVisualChanged() { specCanvas.requestPaint() }
    function onCStyleChanged() { specCanvas.requestPaint() }
    function onCColorChanged() { specCanvas.requestPaint() }
    function onCSchemeChanged() { specCanvas.requestPaint() }
    function onU_timeChanged() { specCanvas.requestPaint() }
  }
  ShaderEffectSource {
    id: specTex
    sourceItem: specCanvas
    live: true
    hideSource: true
    textureSize: Qt.size(32, 4)
  }

  ShaderEffect {
    id: fx
    anchors.fill: parent
    // sampler2D MUST be a Texture/ShaderEffectSource type, not `property var`.
    property ShaderEffectSource u_tex: specTex
    fragmentShader: Qt.resolvedUrl("visual.qsb")
  }
}
