import QtQuick
import Quickshell
import "." as App

ShellRoot {
  id: probe
  property int index: 0
  property bool threaded: Quickshell.env("OMAVIZ_CANVAS_STRATEGY") === "threaded"
  property var cases: ["bars", "flame", "spikes", "stacks", "horizontal", "mono", "reflection", "scope"]
  property string mode: cases[index] || ""
  function advance() {
    canvasLoader.active = false
    index++
    if (index === cases.length) { console.log("RENDER_PROBE_PASS"); Qt.quit(); return }
    Qt.callLater(function() { canvasLoader.active = true })
  }
  FloatingWindow {
    implicitWidth: 320
    implicitHeight: 160
    color: "#0c0c12"
    Loader {
      id: canvasLoader
      anchors.fill: parent
      sourceComponent: Component {
        App.VisualCanvas {
          renderTarget: Canvas.Image
          renderStrategy: probe.threaded ? Canvas.Threaded : Canvas.Immediate
          barCount: 32
          visual: probe.mode === "scope" ? "Oscilloscope" : "Bars"
          fire: probe.mode === "flame"
          spikes: probe.mode === "spikes"
          stacks: probe.mode === "stacks"
          mono: probe.mode === "mono"
          reflect: probe.mode === "reflection"
          wash: probe.mode === "reflection"
          gradientDir: probe.mode === "horizontal" ? "horizontal" : "vertical"
          barColorCustom: true
          barColorFrom: "#245ba8"
          barColorTo: "#f4b968"
        }
      }
      onLoaded: {
        var samples = [], wave = []
        for (var i = 0; i < 32; i++) samples.push(0.15 + 0.8 * Math.abs(Math.sin(i * 0.31)))
        for (var j = 0; j < 128; j++) wave.push(0.6 * Math.sin(j * 0.18))
        item.bands = samples
        item.wave = wave
        capture.restart()
      }
    }
    Timer {
      id: capture
      interval: 200
      onTriggered: {
        var cv = canvasLoader.item
        console.log("RENDER_BACKEND api=" + cv.GraphicsInfo.api + " strategy=" + cv.renderStrategy + " mode=" + probe.mode)
        var image = cv.toDataURL("image/png")
        if (image.indexOf("data:image/png;base64,") !== 0) {
          console.error("RENDER_PROBE_FAILED export"); Qt.quit(); return
        }
        console.log("RENDER_IMAGE " + probe.mode + " " + image.slice(image.indexOf(",") + 1))
        probe.advance()
      }
    }
  }
}
