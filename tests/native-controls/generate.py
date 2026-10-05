"""Exercise the actual inline controls; only shell theme values are stubbed."""
from pathlib import Path
import sys
import shutil
repo=Path(__file__).resolve().parents[2]
out=Path(sys.argv[1]); out.mkdir(parents=True,exist_ok=True)
commons=out/'qs'/'Commons'; commons.mkdir(parents=True,exist_ok=True)
(commons/'qmldir').write_text('module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\nsingleton Border 1.0 Border.qml\n')
(commons/'Style.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property int cornerRadius: 6; property var font: ({family:"Sans Serif",body:14,bodySmall:12}); property var spacing: ({controlHeight:36,md:6}); function space(n) { return n } }')
(commons/'Color.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property color accent: "#55aaff"; property color foreground:"white"; property color background:"black"; property var popups: ({background:"#202020"}) }')
(commons/'Border.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function flat(c,n) { return {} } }')
shutil.copy2('/usr/share/omarchy/shell/Ui/PanelSlider.qml',out/'PanelSlider.qml')
(out/'BorderSurface.qml').write_text('import QtQuick\nRectangle { property var borderSpec: ({}) }')
controls=(repo/'Panel.qml').read_text().split('// ---- Reusable components ----',1)[1]
(out/'scene.qml').write_text('''import QtQuick
import QtQuick.Controls
import qs.Commons
Rectangle {
 id: root; width:480; height:220; color:"black"
 property color fg: "white"
 function revealControl(item) {}
 property int actions:0
 property int clicks: 0
 property int lastSelection: -1
 property string accepted: ""
 Chip { objectName:"chip"; x:10;y:10;width:100;chipLabel:"Custom"; onChipClicked:root.clicks++ }
 ModeSelect { objectName:"select"; x:140;y:10;width:260;model:["Waves","Strings","Siri"]; onActivated: function(index) { root.lastSelection=index } }
 HexField { objectName:"hex"; x:10;y:90;width:200; value:"#123456"; onAccept:function(v) { root.accepted=v; value=v } }
 ActionText { objectName:"link"; x:250;y:90;text:"Show";color:"white"; onActivated:root.actions++ }
 PaletteSwatch { objectName:"swatch";x:320;y:90;width:30;height:24;color:"cyan"; onActivated:root.actions++ }
 OptionSlider { objectName:"slider";x:10;y:150;width:300;minimum:.5;maximum:2;step:.1;value:1;onReleased:function(v) { value=v } }
''' + controls)

# Use the current desktop controls verbatim with an isolated MPRIS stand-in.
desktop=(repo/'Desktop.qml').read_text()
hover=desktop[desktop.index('  // Keyboard access'):desktop.index('  Column {',desktop.index('  // Keyboard access'))]
controls=desktop[desktop.index('  function togglePlayback()'):desktop.index('  // Heartbeats have their own file:')]
controls=controls.replace('id: trayBox','id: trayBox; objectName:"tray"').replace('id: playAction','id: playAction; objectName:"playback"').replace('id: closeAction','id: closeAction; objectName:"close"')
start=desktop.index('      Loader {', desktop.index('// One active instance'))
viewport=desktop[start:desktop.index('      Component {',start)].replace('id: vizLoader', 'id: vizLoader; objectName: "viewport"')
(out/'desktop.qml').write_text("""import QtQuick
import QtQuick.Controls
Rectangle {
 id: win; width:600; height:200
 property var vizConfig: ({visual:"Siri",enabled:true})
 Component { id:canvasComp; Item {} }
 property Item contentItem: win
 property var preferredPlayer: null
 property bool closed:false
 property QtObject activePlayer: QtObject {
   property bool canControl:true
   property bool canPlay:true
   property bool canPause:true
   property bool canTogglePlaying:true
   property bool isPlaying:true
   function play() { isPlaying=true }
   function pause() { isPlaying=false }
   function togglePlaying() { isPlaying=!isPlaying }
 }
 property string trackArt:""
 property string playerSource:"Test player"
 property string trackTitle:"Hover and keyboard test"
 property string trackArtist:"Test artist"
 property string modeName:"Omaviz"
 function setDesktopActive(v) { closed=!v }
 Timer { id:closeTimer }
"""+viewport+hover+controls+'}')
