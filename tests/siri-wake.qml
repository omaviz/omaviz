import QtQuick
import ".." as O

Rectangle {
    width: 320; height: 160; color: "black"
    property int step: 0
    property real settledPhase: 0
    O.VisualCanvas {
        id: canvas
        anchors.fill: parent
        visual: "Siri"
        silent: true
        wave: [.1]
    }
    Timer {
        interval: 400; repeat: true; running: step < 4
        onTriggered: {
            if (step === 0) settledPhase = canvas._phase
            if (step === 1) {
                if (canvas._phase !== settledPhase) throw new Error("Siri did not settle")
                canvas.waveSerial++ // New samples with exactly the same RMS.
            }
            if (step === 2) {
                if (canvas._phase <= settledPhase) throw new Error("Equal-RMS audio did not wake Siri")
                settledPhase = canvas._phase
            }
            if (step === 3) {
                if (canvas._phase !== settledPhase) throw new Error("Unchanged compact audio kept Siri awake")
                console.log("SIRI_WAKE_PASS")
            }
            step++
        }
    }
}
