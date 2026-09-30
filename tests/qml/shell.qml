import QtQuick
import Quickshell
import "." as App

ShellRoot {
  id: test
  property int stage: 0
  property int ticks: 0
  App.SettingsDocument { id: settings; path: Quickshell.env("OMAVIZ_TEST_CONFIG"); writable: true; pollInterval: 25 }
  App.SettingsDocument { id: observer; path: settings.path; pollInterval: 25 }
  App.EngineFeed {
    id: feed
    active: false
    executable: Quickshell.env("OMAVIZ_TEST_ENGINE")
    sourceSpec: "gen=tone"
    bandCount: 16
  }
  Timer {
    interval: 25; running: true; repeat: true
    onTriggered: {
      if (++test.ticks > 400) { console.error("COMPONENT_TEST_FAILED stage=" + test.stage); Qt.quit(); return }
      if (test.stage === 0 && settings.ready && observer.ready) {
        settings.patch("desktop", {peaks: false})
        settings.patch("desktop", {reflect: false, bar_color_to: "#123456"})
        feed.active = true
        test.stage = 1
      } else if (test.stage === 1 && observer.config.barColorTo === "#123456" && feed.bands.length === 16) {
        if (observer.config.peaks || observer.config.reflect || settings.error !== "") {
          console.error("COMPONENT_TEST_FAILED persistence"); Qt.quit(); return
        }
        feed.waveEnabled = true
        test.stage = 2
      } else if (test.stage === 2 && feed.wave.length > 0) {
        feed.active = false
        feed.bandCount = 32
        feed.active = true
        test.stage = 3
      } else if (test.stage === 3 && feed.bands.length === 32) {
        feed.active = false
        test.stage = 4
      } else if (test.stage === 4 && !feed.started && feed.bands.length === 0) {
        feed.executable = "/nonexistent/omaviz-test-engine"
        feed.active = true
        test.stage = 5
      } else if (test.stage === 5 && feed.failures > 0) {
        feed.active = false
        feed.executable = Quickshell.env("OMAVIZ_TEST_ENGINE")
        feed.active = true
        test.stage = 6
      } else if (test.stage === 6 && feed.bands.length === 32) {
        feed.active = false
        test.stage = 7
      } else if (test.stage === 7 && !feed.started) {
        console.log("COMPONENT_TEST_PASS")
        Qt.quit()
      }
    }
  }
}
