import QtQuick
import "glspectrum.js" as GLpack

// GPU visualization renderer (v7.5, Winamp-style bars).
// QML ShaderEffect driven by visual.qsb.
// 32x12 texture layout:
//   row 0  spectrum magnitudes (R)
//   row 1  peak-hold (JS-maintained) (R)
//   row 2  R=visual(0/1)  G=colorSource(0 theme/1 custom)  B=unused
//   row 3  R=time (for background animation)
//   row 4  R=border(0/1)  G=unused  B=unused
//   row 5  custom color RGB
//   row 6  theme bottom RGB
//   row 7  theme top RGB
//   row 8  R=fire(0/1)  G=unused  B=unused
//   row 9  R=peaks(0/1)  G=falloff(0..1)  B=unused  A=unused
//   row 10 R=alpha(0..1)  G=unused  B=unused  A=unused
//   row 11 unused
//
// Unused branches (lines, fade, grid, zoom, thickness, oscilloscope) remain in
// the shader for compatibility but are not exposed in the panel.

Item {
  id: root
  property var bands: []
  property bool silent: false
  property string visual: "Bars"          // "Bars" | "Oscilloscope"
  property string colorSource: "theme"    // "theme" | "custom"
  property color customColor: "#5ec8ff"
  // Defaults seeded from the active Omarchy theme (Matte Black) per
  // THEME_PALETTE.md so the bar gradient matches the current theme out of the box.
  property color themeBottom: "#e68e0d"
  property color themeTop: "#f59e0b"
  // Winamp-style bar options
  property bool fire: false
  property bool peaks: true
  property real falloff: 0.5
  property bool border: true
  property real alpha: 1.0
  // (legacy, unused) eqThickness kept for compat

  readonly property var packed: silent
    ? (function () { var z = []; for (var i = 0; i < 32; i++) z.push(0); return z })()
    : GLpack.packBands(bands, 32)

  property var peakArr: (function () { var z = []; for (var i = 0; i < 32; i++) z.push(0); return z })

  readonly property int   cVisual: (visual === "Oscilloscope") ? 1 : 0
  readonly property int   cColorSrc: (colorSource === "custom") ? 1 : 0
  readonly property int   cFire: fire ? 1 : 0
  readonly property int   cPeaks: peaks ? 1 : 0
  readonly property int   cBorder: border ? 1 : 0
  property real u_time: 0
  NumberAnimation on u_time { running: true; loops: Animation.Infinite; from: 0; to: 1000; duration: 1000000 }

  function updatePeaks() {
    var f = Math.max(0.05, 1.0 - Math.min(1.0, root.falloff) * 0.12)
    for (var i = 0; i < 32; i++) {
      var v = packed[i] || 0
      if (v >= root.peakArr[i]) root.peakArr[i] = Math.max(root.peakArr[i], v)
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
      // row 1: peak-hold (JS-maintained)
      for (var j = 0; j < 32; j++) {
        var pg = Math.round(Math.min(1, Math.max(0, root.peakArr[j] || 0)) * 255)
        ctx.fillStyle = "rgb(" + pg + "," + pg + "," + pg + ")"; ctx.fillRect(j, 1, 1, 1)
      }
      function row(y, r,g,b,a){ ctx.fillStyle="rgba("+r+","+g+","+b+","+(a!==undefined?a:255)+")"; ctx.fillRect(0,y,32,1) }
      // row 2: visual + colorSource
      row(2, cVisual*255, cColorSrc*255, 0)
      // row 3: time
      row(3, Math.round((u_time%1000)/1000*255), 0, 0)
      // row 4: border
      row(4, cBorder*255, 0, 0)
      // row 5: custom color RGB
      row(5, Math.round(customColor.r*255), Math.round(customColor.g*255), Math.round(customColor.b*255))
      // row 6: theme bottom RGB
      row(6, Math.round(themeBottom.r*255), Math.round(themeBottom.g*255), Math.round(themeBottom.b*255))
      // row 7: theme top RGB
      row(7, Math.round(themeTop.r*255), Math.round(themeTop.g*255), Math.round(themeTop.b*255))
      // row 8: fire toggle (0/255)
      row(8, cFire*255, 0, 0)
      // row 9: peaks toggle + falloff
      row(9, cPeaks*255, Math.round(falloff*255), 0)
      // row 10: alpha (0..1)
      row(10, Math.round(Math.min(1, Math.max(0, alpha))*255), 0, 0)
        // row 11: reserved for scope params (R=style(0 line/1 dot), G=colorMode(0 solid), B=grid(0/1))
      // defaults: line style, solid color, no grid
      row(11, 0, 0, 0)
    }
    Component.onCompleted: requestPaint()
  }

  Connections {
    target: root
    function onBandsChanged() { updatePeaks(); specCanvas.requestPaint() }
    function onCFireChanged() { specCanvas.requestPaint() }
    function onCPeaksChanged() { specCanvas.requestPaint() }
    function onFalloffChanged() { updatePeaks(); specCanvas.requestPaint() }
    function onCColorSrcChanged() { specCanvas.requestPaint() }
    function onCustomColorChanged() { specCanvas.requestPaint() }
    function onThemeBottomChanged() { specCanvas.requestPaint() }
    function onThemeTopChanged() { specCanvas.requestPaint() }
    function onU_timeChanged() { specCanvas.requestPaint() }
    function onAlphaChanged() { specCanvas.requestPaint() }
    function onCBorderChanged() { specCanvas.requestPaint() }
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