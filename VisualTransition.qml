import QtQuick
import "ModelStore.js" as Store

QtObject {
  id: state
  property var config: Store.defaultConfig()
  property var presented: Store.defaultConfig()
  property var pending: config
  property real fade: 1
  property bool ready: false
  function sync() {
    pending = config
    if (!ready) { presented = config; return }
    if (transition.running) return
    if ((config.shuffle || presented.shuffle) && Store.visualSignature(config) !== Store.visualSignature(presented)) transition.start()
    else presented = config
  }
  onConfigChanged: sync()
  property SequentialAnimation transition: SequentialAnimation {
    NumberAnimation { target: state; property: "fade"; to: 0; duration: 500; easing.type: Easing.InOutQuad }
    ScriptAction { script: state.presented = state.pending }
    NumberAnimation { target: state; property: "fade"; to: 1; duration: 700; easing.type: Easing.InOutQuad }
    onFinished: state.sync()
  }
  Component.onCompleted: { presented = config; ready = true }
}
