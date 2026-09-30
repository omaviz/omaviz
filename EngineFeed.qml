import QtQuick
import Quickshell.Io
import "ModelStore.js" as Store

// Process transitions wait for onExited; no false/true races or callLater
// guesses about when termination completes. Both surfaces share this owner.
Item {
  id: feed
  property bool active: true
  property bool waveEnabled: false
  property int bandCount: 128
  property string sourceSpec: "auto"
  property string executable: Store.engineBin
  property var bands: []
  property var wave: []
  property bool silent: true
  property string source: ""
  property int failures: 0
  property bool restarting: false
  property bool started: false
  property bool ready: false
  readonly property var desiredCommand: [executable, "--source", sourceSpec, "--bands", String(bandCount)].concat(waveEnabled ? ["--wave"] : [])

  function reconcile() {
    if (!ready) return
    retry.stop()
    startupDeadline.stop()
    if (!active) {
      restarting = false
      process.running = false
      if (process.processId === 0) started = false
      bands = []; wave = []; silent = true
      return
    }
    if (started) {
      restarting = true
      process.running = false
    } else if (!restarting) start()
  }
  function start() {
    if (!active) return
    restarting = false
    started = true
    process.command = desiredCommand
    process.running = true
    startupDeadline.restart()
  }
  function retryLater() {
    if (!active) return
    bands = []; wave = []; silent = true
    failures = Math.min(failures + 1, 20)
    retry.interval = Math.min(30000, 1500 * failures)
    retry.restart()
  }
  onActiveChanged: reconcile()
  onDesiredCommandChanged: reconcile()
  Component.onCompleted: { ready = true; reconcile() }
  Process {
    id: process
    stdout: SplitParser {
      onRead: function(line) {
        if (!feed.active) return
        var frame = Store.decodeFrame(line)
        if (!frame) return
        feed.failures = 0
        if (frame.wave) feed.wave = frame.wave
        else {
          feed.bands = frame.bands
          feed.silent = frame.silent
          feed.source = frame.source
        }
      }
    }
    onStarted: startupDeadline.stop()
    onExited: {
      startupDeadline.stop()
      feed.started = false
      if (!feed.active) return
      if (feed.restarting) { feed.start(); return }
      feed.retryLater()
    }
  }
  // Failed-to-start may not emit exited; bound that transition too.
  Timer {
    id: startupDeadline
    interval: 1500
    onTriggered: {
      process.running = false
      feed.started = false
      feed.restarting = false
      feed.retryLater()
    }
  }
  Timer { id: retry; onTriggered: feed.start() }
}
