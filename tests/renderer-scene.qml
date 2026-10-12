import QtQuick
import "../native" as Native

// Bounded native probe fixture. Frozen runs submit exactly 90 identical
// timesteps before capture; animated runs exercise the production 60 Hz API.
Rectangle {
    width: 754; height: 405; color: "black"
    property bool animated: false
    property real amplitude: .07
    property real phaseOffset: 0
    property bool custom: false
    property bool mono: false
    property bool monoLight: false
    property real gain: 1
    property real lineWidth: 2
    property bool compactStrings: false
    property int frame: 0
    property bool ready: false
    // Let the surface and scene graph initialize before the fixed timeline.
    // Otherwise compositor startup can coalesce the first audio submissions.
    Timer { interval: 500; running: true; onTriggered: parent.ready = true }
    property real accumulator: 0
    property var inputWave: {
        let a=[]
        for(let i=0;i<128;i++) a.push(amplitude*Math.sin(i*.14))
        return a
    }
    property var inputBands: [.1,.5,.8,.3,.2,.7,.9,.4]
    property bool inputSilent: false
    Native.VisualGeometry {
        id: mesh
        width: parent.width - 8
        height: Math.min(parent.height - 8, width/3)
        anchors.centerIn: parent
        style: ({mode:"Siri", compactStrings:compactStrings, gain:gain, lineWidth:lineWidth, custom:custom, mono:mono, monoLight:monoLight,
                 bottom:"#008c95", top:"#c5c94b", middle:"#663cc8", middleEnabled:true})
    }
    FrameAnimation {
        running: ready && (animated || frame<90)
        onTriggered: {
            accumulator += Math.min(frameTime, .1)
            if(accumulator+.00001 < 1/60) return
            accumulator %= 1/60
            frame++
            let bands=inputBands
            if (compactStrings && bands.length) {
                let drives=[]
                for(let layer=0;layer<16;layer++) {
                    let center=Math.min(bands.length-1,Math.floor((layer+.5)/16*bands.length)), drive=0
                    for(let tap=-2;tap<=2;tap++) drive=Math.max(drive,bands[Math.max(0,Math.min(bands.length-1,center+tap))])
                    drives.push(drive)
                }
                bands=drives
            }
            mesh.submit(bands,[],inputWave,phaseOffset+frame/60)
        }
    }
}
