import QtQuick
import "glspectrum.js" as GLpack

// GPU visualization renderer (v7.6, Winamp-style DENSE spectrum + WAVE).
// QML ShaderEffect driven by visual.qsb.
// density (desktop.density, default 64) x 12 texture layout:
//   row 0  spectrum magnitudes (R)
//   row 1  peak-hold (JS-maintained) (R)
//   row 2  R=visual(0 Bars /1 Oscilloscope /2 Wave)  G=colorSource(0 theme/1 custom)  B=unused
//   row 3  R=time (for background animation)
//   row 4  R=border(0/1)  G=unused  B=unused
//   row 5  custom color RGB
//   row 6  theme bottom RGB
//   row 7  theme top RGB
//   row 8  R=fire(0/1)  G=unused  B=unused
//   row 9  R=peaks(0/1)  G=falloff(0..1)  B=unused  A=unused
//   row 10 R=alpha(0..1)  G=unused  B=unused  A=unused
//   row 11 R=density/256 (NB bar count)  G=barGap(0..1)  B=unused
//
// Unused branches (lines, fade, grid, zoom, thickness) remain in
// the shader for compatibility but are not exposed in the panel.

Item {
  id: root
  property var bands: []
  property bool silent: false
  property string visual: "Bars"          // "Bars" | "Oscilloscope" | "Wave"
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
  // Desktop-window spectrum resolution (dense). Independent of the mini bar's
  // 32-band feed; the engine is spawned with --bands density (Desktop.qml).
  property int density: 64
  // Bar separation (0..1 of one bar slot). 0 = contiguous (immersive dense
  // spectrum, used by the desktop window); ~0.10 = slim gaps (mini bar default).
  // Packed into control-texture row 11 G (no free-standing uniform).
  property real barGap: 0.10

  readonly property var packed: silent
    ? (function () { var z = []; for (var i = 0; i < root.density; i++) z.push(0); return z })()
    : GLpack.packBands(bands, root.density)

  property var peakArr: (function () { var z = []; for (var i = 0; i < root.density; i++) z.push(0); return z })

  // Visual control code packed into texture row 2 R as a raw 0/1/2 integer
  // (the shader decodes it with int(ctrl().r*255.0+0.5)). Bars=0, Osc=1, Wave=2.
  readonly property int   cVisual: (visual === "Wave") ? 2 : (visual === "Oscilloscope") ? 1 : 0
  readonly property int   cColorSrc: (colorSource === "custom") ? 1 : 0
  readonly property int   cFire: fire ? 1 : 0
  readonly property int   cPeaks: peaks ? 1 : 0
  readonly property int   cBorder: border ? 1 : 0
  property real u_time: 0
  NumberAnimation on u_time { running: true; loops: Animation.Infinite; from: 0; to: 1000; duration: 1000000 }

  function updatePeaks() {
    var f = Math.max(0.05, 1.0 - Math.min(1.0, root.falloff) * 0.12)
    var n = root.density
    for (var i = 0; i < n; i++) {
      var v = packed[i] || 0
      if (v >= root.peakArr[i]) root.peakArr[i] = Math.max(root.peakArr[i], v)
      else root.peakArr[i] = root.peakArr[i] * f
    }
  }

  Canvas {
    id: specCanvas
    width: root.density; height: 12
    visible: true
    // ADR-0005: force NEAREST on the control texture. A layer renders this
    // Canvas through an FBO and inherits NEAREST when smoothing is disabled;
    // the ShaderEffectSource (specTex) samples that layer texture. Qt6 exposes
    // no `filtering` property on ShaderEffectSource, so this is the only
    // QML-facing way to keep the discrete 8-bit control codes exact.
    layer.enabled: true
    layer.smooth: false
    onPaint: {
      var ctx = getContext("2d")
      var n = root.density
      ctx.clearRect(0, 0, width, height)
      // row 0: spectrum
      for (var i = 0; i < n; i++) {
        var g = Math.round(Math.min(1, Math.max(0, packed[i] || 0)) * 255)
        ctx.fillStyle = "rgb(" + g + "," + g + "," + g + ")"; ctx.fillRect(i, 0, 1, 1)
      }
      // row 1: peak-hold (JS-maintained)
      for (var j = 0; j < n; j++) {
        var pg = Math.round(Math.min(1, Math.max(0, root.peakArr[j] || 0)) * 255)
        ctx.fillStyle = "rgb(" + pg + "," + pg + "," + pg + ")"; ctx.fillRect(j, 1, 1, 1)
      }
      function row(y, r,g,b,a){ ctx.fillStyle="rgba("+r+","+g+","+b+","+(a!==undefined?a:255)+")"; ctx.fillRect(0,y,n,1) }
      // row 2: visual (raw 0/1/2) + colorSource
      row(2, cVisual, cColorSrc*255, 0)
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
      // row 11: R = density/256 (NB passed to shader), G = barGap (0..1)
      row(11, Math.round(root.density / 256.0 * 255), Math.round(Math.min(1, Math.max(0, root.barGap)) * 255), 0)
    }
    Component.onCompleted: requestPaint()
  }

  Connections {
    target: root
    function onBandsChanged() { updatePeaks(); specCanvas.requestPaint() }
    function onDensityChanged() { peakArr = (function () { var z = []; for (var i = 0; i < root.density; i++) z.push(0); return z })(); specCanvas.requestPaint() }
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
    function onVisualChanged() { specCanvas.requestPaint() }
    function onBarGapChanged() { specCanvas.requestPaint() }
  }

  ShaderEffectSource {
    id: specTex
    sourceItem: specCanvas
    live: true
    hideSource: true
    textureSize: Qt.size(root.density, 12)
    // NEAREST sampling is REQUIRED: the control texture packs discrete 8-bit
    // codes (visual 0/1/2 in row 2 R, toggles in rows 8/9, density in row 11)
    // as exact values. Qt6 has NO `filtering` property on ShaderEffectSource
    // (a `filtering: ...` line is a silent no-op), so NEAREST is forced via the
    // source item's layer: a layer is rendered through an FBO and inherits
    // NEAREST when `smooth:false`. Without this the default LINEAR filtering
    // averages a control row with its vertical neighbours (e.g. the animated
    // time row 3), so a packed value 2 (R=2/255) reads back as ~1 -> wave
    // silently renders as the oscilloscope branch. See ADR-0005.
  }

  ShaderEffect {
    id: fx
    anchors.fill: parent
    property ShaderEffectSource u_tex: specTex
    fragmentShader: Qt.resolvedUrl("visual.qsb")
  }
}
