import QtQuick
import "glspectrum.js" as GLpack

// GPU visualization renderer (v7.4).
// QML ShaderEffect driven by a precompiled GLSL shader (visual.qsb).
// 32x12 control/spectrum texture; see shaders/visual.frag for the row map.
// All visualization options (Winamp Spectrum Analyzer + Oscilloscope) are
// passed via texture rows so we avoid Qt6 UBO upload pitfalls.

Item {
  id: root
  property var bands: []
  property bool silent: false
  property string visual: "Bars"          // "Bars"(Analyzer) | "Oscilloscope"
  property bool colorSync: true
  property int barCount: 0
  property int colourScheme: 0
  property color monoColor: "#dce0eb"
  // window options
  property bool border: true
  property bool render3d: false
  property string colorSource: "theme"
  property color customColor: "#5ec8ff"
  property color themeBottom: "#19e0d4"
  property color themeTop: "#a45cff"
  // Spectrum Analyzer (equalizer) options
  property string eqMode: "bars"          // bars | lines
  property string eqColor: "fire"        // solid | line | fade | fire
  property bool eqGrid: false
  property bool eqPeaks: true
  property real eqFalloff: 0.5
  property string eqZoom: "1x"           // 1x | 2x | 4x
  property int eqThickness: 2
  // Oscilloscope options
  property string scopeStyle: "line"      // line | dot
  property string scopeColor: "solid"     // solid | line | fade | fire
  property bool scopeGrid: false
  property bool scopeScan: false
  property bool scopeCentered: false
  property int scopeThickness: 2

  readonly property var packed: silent
    ? (function () { var z = []; for (var i = 0; i < 32; i++) z.push(0); return z })()
    : GLpack.packBands(bands, 32)
  // Peak-hold array (per band), JS-maintained with falloff.
  property var peakArr: (function () { var z = []; for (var i = 0; i < 32; i++) z.push(0); return z })
  readonly property real u_peak: GLpack.peakOf(packed)

  readonly property int   cVisual: (visual === "Oscilloscope") ? 1 : 0
  readonly property int   cColorSrc: (colorSource === "custom") ? 1 : 0
  readonly property int   cBorder: border ? 1 : 0
  readonly property int   c3d:     render3d ? 1 : 0
  readonly property int   cEqMode: (eqMode === "lines") ? 1 : 0
  readonly property int   cEqColor: (eqColor === "fire") ? 3 : (eqColor === "fade") ? 2 : (eqColor === "line") ? 1 : 0
  readonly property int   cEqGrid: eqGrid ? 1 : 0
  readonly property int   cEqPeaks: eqPeaks ? 1 : 0
  readonly property int   cEqZoom: (eqZoom === "4x") ? 2 : (eqZoom === "2x") ? 1 : 0
  readonly property int   cScStyle: (scopeStyle === "dot") ? 1 : 0
  readonly property int   cScColor: (scopeColor === "fire") ? 3 : (scopeColor === "fade") ? 2 : (scopeColor === "line") ? 1 : 0
  readonly property int   cScGrid: scopeGrid ? 1 : 0
  readonly property int   cScScan: scopeScan ? 1 : 0
  readonly property int   cScCtr: scopeCentered ? 1 : 0
  readonly property int   cEqThickness: eqThickness * 80  // 1..4 -> 80,160,240,320
  readonly property int   cScThickness: scopeThickness * 80
  property real u_time: 0
  NumberAnimation on u_time { running: true; loops: Animation.Infinite; from: 0; to: 1000; duration: 1000000 }

  function updatePeaks() {
    var f = Math.max(0.05, 1.0 - root.eqFalloff * 0.12)
    for (var i = 0; i < 32; i++) {
      var v = packed[i] || 0
      if (v >= root.peakArr[i]) root.peakArr[i] = v
      else root.peakArr[i] = root.peakArr[i] * f
    }
  }

  Canvas {
    id: specCanvas
    width: 32; height: 12
    visible: true
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      // row 0: spectrum
      for (var i = 0; i < 32; i++) {
        var g = Math.round(Math.min(1, Math.max(0, packed[i] || 0)) * 255)
        ctx.fillStyle = "rgb(" + g + "," + g + "," + g + ")"; ctx.fillRect(i, 0, 1, 1)
      }
      // row 1: peak-hold
      for (var j = 0; j < 32; j++) {
        var pg = Math.round(Math.min(1, Math.max(0, root.peakArr[j] || 0)) * 255)
        ctx.fillStyle = "rgb(" + pg + "," + pg + "," + pg + ")"; ctx.fillRect(j, 1, 1, 1)
      }
      function row(y, r,g,b,a){ ctx.fillStyle="rgba("+r+","+g+","+b+","+(a!==undefined?a:255)+")"; ctx.fillRect(0,y,32,1) }
      row(2, cVisual*255, cColorSrc*255, 0)
      row(3, Math.round((u_time%1000)/1000*255), 0, 0)
      row(4, cBorder*255, c3d*255, 0)
      var cr=Math.round(customColor.r*255), cg=Math.round(customColor.g*255), cb=Math.round(customColor.b*255)
      row(5, cr, cg, cb)
      var br=Math.round(themeBottom.r*255), bg=Math.round(themeBottom.g*255), bb=Math.round(themeBottom.b*255)
      row(6, br, bg, bb)
      var tr=Math.round(themeTop.r*255), tg=Math.round(themeTop.g*255), tb=Math.round(themeTop.b*255)
      row(7, tr, tg, tb)
      row(8, cEqMode*255, cEqColor*255, cEqGrid*255)
      row(9, cEqPeaks*255, Math.round(eqFalloff*255), cEqZoom*255, cEqThickness)
      row(10, cScStyle*255, cScColor*255, cScGrid*255)
      row(11, cScScan*255, cScCtr*255, cScThickness)
    }
    Component.onCompleted: requestPaint()
  }
  Connections {
    target: root
    function onBandsChanged() { updatePeaks(); specCanvas.requestPaint() }
    function onCVisualChanged() { specCanvas.requestPaint() }
    function onCColorSrcChanged() { specCanvas.requestPaint() }
    function onCBorderChanged() { specCanvas.requestPaint() }
    function onC3dChanged() { specCanvas.requestPaint() }
    function onCEqModeChanged() { specCanvas.requestPaint() }
    function onCEqColorChanged() { specCanvas.requestPaint() }
    function onCEqGridChanged() { specCanvas.requestPaint() }
    function onCEqPeaksChanged() { specCanvas.requestPaint() }
    function onCEqZoomChanged() { specCanvas.requestPaint() }
    function onCScStyleChanged() { specCanvas.requestPaint() }
    function onCScColorChanged() { specCanvas.requestPaint() }
    function onCScGridChanged() { specCanvas.requestPaint() }
    function onCScScanChanged() { specCanvas.requestPaint() }
    function onCScCtrChanged() { specCanvas.requestPaint() }
    function onU_timeChanged() { specCanvas.requestPaint() }
    function onCustomColorChanged() { specCanvas.requestPaint() }
    function onThemeBottomChanged() { specCanvas.requestPaint() }
    function onThemeTopChanged() { specCanvas.requestPaint() }
  }
  ShaderEffectSource {
    id: specTex
    sourceItem: specCanvas
    live: true
    hideSource: true
    textureSize: Qt.size(32, 12)
  }
  ShaderEffect {
    id: fx
    anchors.fill: parent
    property ShaderEffectSource u_tex: specTex
    fragmentShader: Qt.resolvedUrl("visual.qsb")
  }
}