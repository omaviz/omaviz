import QtQuick
import "glspectrum.js" as GLpack

// GPU visualization renderer (v7.2).
// QML ShaderEffect driven by a precompiled GLSL shader (visual.qsb).
// Data path: live `bands` -> packed to 32 floats + scalar controls -> painted
// into a visible 32x7 Canvas -> exposed as a ShaderEffectSource texture (u_tex).
//   row 0 : spectrum magnitudes (R)
//   row 1 : R=visual G=style B=color
//   row 2 : R=peak G=time B=colorSrc(0 theme /1 custom)
//   row 3 : R=border G=render3d
//   row 4 : custom color RGB
//   row 5 : theme bottom color RGB
//   row 6 : theme top color RGB

Item {
  id: root
  property var bands: []
  property bool silent: false
  property string visual: "Bars"
  property string style: "Classic"
  property bool colorSync: true
  property int barCount: 0
  property int colourScheme: 0
  property color monoColor: "#dce0eb"
  // v7.2 options
  property bool border: true
  property bool render3d: false
  property string colorSource: "theme"     // "theme" or "custom"
  property color customColor: "#5ec8ff"
  property color themeBottom: "#19e0d4"    // theme-dominant bottom color
  property color themeTop: "#a45cff"       // theme-dominant top color

  readonly property var packed: silent
    ? (function () { var z = []; for (var i = 0; i < 32; i++) z.push(0); return z })()
    : GLpack.packBands(bands, 32)
  readonly property real u_peak: GLpack.peakOf(packed)

  readonly property int   cVisual: (visual === "Wave") ? 1 : 0
  readonly property int   cStyle:  (style === "Fire" && visual !== "Wave") ? 1 : 0
  readonly property int   cColor:  colorSync ? 1 : 0
  readonly property int   cColorSrc: (colorSource === "custom") ? 1 : 0
  readonly property int   cBorder: border ? 1 : 0
  readonly property int   c3d:     render3d ? 1 : 0
  property real u_time: 0
  NumberAnimation on u_time { running: true; loops: Animation.Infinite; from: 0; to: 1000; duration: 1000000 }

  Canvas {
    id: specCanvas
    width: 32; height: 7
    visible: true
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      for (var i = 0; i < 32; i++) {
        var v = packed[i] || 0
        var g = Math.round(Math.min(1, Math.max(0, v)) * 255)
        ctx.fillStyle = "rgb(" + g + "," + g + "," + g + ")"
        ctx.fillRect(i, 0, 1, 1)
      }
      ctx.fillStyle = "rgb(" + (cVisual*255) + "," + (cStyle*255) + "," + (cColor*255) + ")"
      ctx.fillRect(0, 1, 32, 1)
      var pk = Math.round(Math.min(1, Math.max(0, u_peak)) * 255)
      var tm = Math.round(Math.min(1, Math.max(0, (u_time % 1000) / 1000)) * 255)
      var cs = Math.round(Math.min(1, Math.max(0, cColorSrc)) * 255)
      ctx.fillStyle = "rgb(" + pk + "," + tm + "," + cs + ")"
      ctx.fillRect(0, 2, 32, 1)
      ctx.fillStyle = "rgb(" + (cBorder*255) + "," + (c3d*255) + ",0)"
      ctx.fillRect(0, 3, 32, 1)
      var cr = Math.round(customColor.r*255), cg = Math.round(customColor.g*255), cb = Math.round(customColor.b*255)
      ctx.fillStyle = "rgb(" + cr + "," + cg + "," + cb + ")"
      ctx.fillRect(0, 4, 32, 1)
      var br = Math.round(themeBottom.r*255), bg = Math.round(themeBottom.g*255), bb = Math.round(themeBottom.b*255)
      ctx.fillStyle = "rgb(" + br + "," + bg + "," + bb + ")"
      ctx.fillRect(0, 5, 32, 1)
      var tr = Math.round(themeTop.r*255), tg = Math.round(themeTop.g*255), tb = Math.round(themeTop.b*255)
      ctx.fillStyle = "rgb(" + tr + "," + tg + "," + tb + ")"
      ctx.fillRect(0, 6, 32, 1)
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
    function onCColorSrcChanged() { specCanvas.requestPaint() }
    function onCBorderChanged() { specCanvas.requestPaint() }
    function onC3dChanged() { specCanvas.requestPaint() }
    function onCustomColorChanged() { specCanvas.requestPaint() }
    function onThemeBottomChanged() { specCanvas.requestPaint() }
    function onThemeTopChanged() { specCanvas.requestPaint() }
    function onU_timeChanged() { specCanvas.requestPaint() }
  }
  ShaderEffectSource {
    id: specTex
    sourceItem: specCanvas
    live: true
    hideSource: true
    textureSize: Qt.size(32, 7)
  }
  ShaderEffect {
    id: fx
    anchors.fill: parent
    property ShaderEffectSource u_tex: specTex
    fragmentShader: Qt.resolvedUrl("visual.qsb")
  }
}
