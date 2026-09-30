import QtQuick
import Quickshell.Io
import "ModelStore.js" as Store
import "SettingsQueue.js" as Queue

// One observable configuration per surface. The desktop is read-only; the bar
// is the sole settings writer. Polling remains a fallback for missed watches.
Item {
  id: document
  property string path: Store.configPath
  property bool writable: false
  property int pollInterval: 500
  readonly property var config: Store.readConfigFromText(text)
  property string text: ""
  property bool ready: false
  property string error: ""
  property var queue: Queue.create("")

  function accept(text) {
    Queue.loaded(queue, text)
    document.text = Queue.current(queue)
    document.ready = true
    flush()
  }
  function patch(section, values) {
    if (!writable || !ready) return false
    var updated = Queue.current(queue)
    for (var key in values) {
      if (Object.prototype.hasOwnProperty.call(values, key))
        updated = Store.writeConfigKey(updated, section, key, values[key])
    }
    if (!Queue.edit(queue, updated)) return false
    document.text = updated
    flush()
    return true
  }
  function flush() {
    if (!writable) return
    var pending = Queue.next(queue)
    if (pending !== null) writer.setText(pending)
  }
  FileView {
    id: reader
    path: document.path
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: document.accept(text())
    onLoadFailed: {
      // Retain the last valid state on transient failures after startup.
      if (!document.ready) document.accept("")
    }
  }
  FileView {
    id: writer
    path: document.path
    printErrors: false
    onSaved: {
      Queue.saved(document.queue)
      document.error = ""
      reader.reload()
    }
    onSaveFailed: {
      Queue.failed(document.queue)
      document.text = Queue.current(document.queue)
      document.error = "Could not save settings"
      console.warn("omaviz: " + document.error)
      reader.reload()
    }
  }
  Timer {
    interval: document.pollInterval
    running: true
    repeat: true
    onTriggered: reader.reload()
  }
}
