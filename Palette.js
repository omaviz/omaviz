.pragma library

// Colour tables shared by the renderer and functional tests.
function build(bottom, top, baseC, tipC) {
    var tipR = Math.round(tipC.r * 255), tipG = Math.round(tipC.g * 255), tipB = Math.round(tipC.b * 255)
    var f = [], p = [], w = []
    for (var k = 0; k <= 100; k++) {
      var t = k / 100, r, g, bl
      if (t < 0.3) {
        var kc = t / 0.3
        r = Math.round(baseC.r * 255 + kc * (255 - baseC.r * 255))
        g = Math.round(baseC.g * 255 + kc * (130 - baseC.g * 255))
        bl = Math.round(baseC.b * 255 + kc * (10 - baseC.b * 255))
      } else {
        var k3 = (t - 0.3) / 0.7
        r = Math.round(255 + (tipR - 255) * k3)
        g = Math.round(130 + (tipG - 130) * k3)
        bl = Math.round(10 + (tipB - 10) * k3)
      }
      f.push("rgba(" + r + "," + g + "," + bl + ",1)")
      p.push("rgba(" + Math.round((bottom[0] + (top[0] - bottom[0]) * t) * 255) + "," + Math.round((bottom[1] + (top[1] - bottom[1]) * t) * 255) + "," + Math.round((bottom[2] + (top[2] - bottom[2]) * t) * 255) + ",1)")
      w.push("rgba(" + Math.round((bottom[0] + (top[0] - bottom[0]) * t) * 255) + "," + Math.round((bottom[1] + (top[1] - bottom[1]) * t) * 255) + "," + Math.round((bottom[2] + (top[2] - bottom[2]) * t) * 255) + ",0.10)")
    }
    return { fire: f, plain: p, wash: w }
}
if (typeof module !== "undefined") module.exports = { build: build }
