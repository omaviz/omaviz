import QtQuick

// Static dotted backdrop (Winamp skin dressing), split out of the
// per-frame bars canvas: the grid never changes, so it paints ONCE per
// size instead of 60x/sec. On a 1500x830 desktop that's ~34K fillRects
// per frame eliminated (~70% of a core back).
Canvas {
  id: dots
  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    ctx.fillStyle = "rgba(255,255,255,0.05)"
    for (var x = 2; x < width; x += 6) {
      for (var y = 2; y < height; y += 6) {
        ctx.fillRect(x, y, 1, 1)
      }
    }
  }
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  Component.onCompleted: requestPaint()
}
