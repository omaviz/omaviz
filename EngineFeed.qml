import QtQuick
import Quickshell.Io
import "ModelStore.js" as Store

// Process transitions wait for onExited; no false/true races or callLater
// guesses about when termination completes. Both surfaces share this owner.
Item {
  id: feed
  property bool active: true
  property bool waveEnabled: false
  property bool siriEnabled: false
  property bool stringsEnabled: false
  property int bandCount: 128
  property string sourceSpec: "auto"
  property string executable: Store.engineBin
  property var bands: []
  property string bandLayout: ""
  property var wave: []
  property real waveRms: -1
  property int waveSerial: 0
  property bool silent: true
  property string source: ""
  property int failures: 0
  property bool restarting: false
  property bool started: false
  property bool ready: false
  property int frameTimeout: 4000
  property string status: "Stopped"
  readonly property var desiredCommand: [executable, "--source", sourceSpec, "--bands", String(bandCount)].concat(siriEnabled ? ["--siri"] : stringsEnabled ? ["--strings"] : waveEnabled ? ["--wave"] : [])

  function stopProcess() {
    process.running = false
    if (process.processId > 0) stopDeadline.restart()
  }
  function reconcile() {
    if (!ready) return
    retry.stop()
    startupDeadline.stop()
    frameDeadline.stop()
    if (!active) {
      restarting = false
      status = "Stopped"
      stopProcess()
      if (process.processId === 0) started = false
      bands = []; wave = []; waveRms = -1; bandLayout = ""; silent = true
      return
    }
    if (started) {
      // Compact and full feeds have different sample layouts. Never expose
      // the old layout to the newly selected visualization during restart.
      bands = []; wave = []; waveRms = -1; bandLayout = ""; silent = true
      restarting = true
      stopProcess()
    } else if (!restarting) start()
  }
  function start() {
    if (!active) return
    restarting = false
    stopDeadline.stop()
    started = true
    status = failures ? "Recovering" : "Connecting"
    process.command = desiredCommand
    process.running = true
    startupDeadline.restart()
    frameDeadline.restart()
  }
  function retryLater() {
    if (!active) return
    bands = []; wave = []; waveRms = -1; bandLayout = ""; silent = true
    failures = Math.min(failures + 1, 20)
    status = "Recovering"
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
        if (!feed.active || feed.restarting) return
        var frame = Store.decodeFrame(line)
        if (!frame) return
        if (frame.wave) {
          feed.waveRms = frame.waveRms === undefined ? -1 : frame.waveRms
          feed.wave = frame.wave
          if (frame.waveSerial !== undefined) feed.waveSerial = frame.waveSerial
        }
        else {
          feed.failures = 0
          frameDeadline.restart()
          feed.status = frame.silent ? "Listening · quiet" : "Listening"
          feed.bandLayout = frame.bandLayout || ""
          feed.bands = frame.bands
          feed.silent = frame.silent
          feed.source = frame.source
        }
      }
    }
    onStarted: startupDeadline.stop()
    onExited: {
      startupDeadline.stop()
      frameDeadline.stop()
      stopDeadline.stop()
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
      stopProcess()
      feed.started = false
      feed.restarting = false
      frameDeadline.stop()
      feed.retryLater()
    }
  }
  Timer { id: retry; onTriggered: feed.start() }
  Timer {
    id: frameDeadline
    interval: feed.frameTimeout
    onTriggered: {
      // Terminate the stale owner; onExited schedules the normal backoff.
      feed.bands = []; feed.wave = []; feed.waveRms = -1
      feed.bandLayout = ""; feed.silent = true
      feed.status = "Recovering"
      stopProcess()
    }
  }
  Timer {
    id: stopDeadline
    interval: 500
    onTriggered: if (process.processId > 0) process.signal(9)
  }
}
