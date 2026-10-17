import QtQuick
import Quickshell
import Quickshell.Io
import "ModelStore.js" as Store

// The app entry point resumes persistent settings before mounting the bar.
// Keep writes in SettingsDocument so asynchronous saves finish before launch.
ShellRoot {
  id: launch
  property bool requested: false
  function resume() {
    if (requested) return
    requested = true
    if (Store.readConfigFromText(settings.text).enabled === false)
      settings.patch("desktop", { enabled: true })
    else enable.running = true
  }
  SettingsDocument {
    id: settings
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omaviz/config.toml"
    writable: true
    onReadyChanged: if (ready) Qt.callLater(launch.resume)
    onSettled: if (launch.requested && config.enabled !== false && !enable.running) enable.running = true
    onErrorChanged: if (error) { console.warn("omaviz: " + error); Qt.quit() }
  }
  Process {
    id: enable
    command: ["omarchy", "plugin", "enable", "org.omaviz.visualizer"]
    stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("omaviz: " + text.trim()) }
    onExited: function(code) {
      if (code === 0) Quickshell.execDetached(["quickshell", "-n", "-p", Store.pluginDir + "/Desktop.qml"])
      else console.warn("omaviz: could not enable the plugin (exit " + code + ")")
      Qt.quit()
    }
  }
}
