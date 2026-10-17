"""Exercise the actual inline controls; only shell theme values are stubbed."""
from pathlib import Path
import sys
import shutil
import re
repo=Path(__file__).resolve().parents[2]
out=Path(sys.argv[1]); out.mkdir(parents=True,exist_ok=True)
commons=out/'qs'/'Commons'; commons.mkdir(parents=True,exist_ok=True)
(commons/'qmldir').write_text('module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\nsingleton Border 1.0 Border.qml\n')
(commons/'Style.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property int cornerRadius: 6; property var font: ({family:"Sans Serif",body:14,bodySmall:12}); property var spacing: ({controlHeight:36,md:6}); function space(n) { return n } }')
(commons/'Color.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property color accent: "#55aaff"; property color foreground:"white"; property color background:"black"; property var popups: ({background:"#202020"}) }')
(commons/'Border.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function flat(c,n) { return {} } function controlSpec() { return {} } }')
shutil.copy2('/usr/share/omarchy/shell/Ui/PanelSlider.qml',out/'PanelSlider.qml')
(out/'BorderSurface.qml').write_text('import QtQuick\nRectangle { property var borderSpec: ({}) }')
controls=(repo/'Panel.qml').read_text().split('// ---- Reusable components ----',1)[1]
(out/'scene.qml').write_text('''import QtQuick
import QtQuick.Controls
import qs.Commons
Rectangle {
 id: root; width:480; height:300; color:"black"
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
 ChoiceGroup { objectName:"choices"; x:10;y:210;width:440; options:[{id:"a",label:"A"},{id:"b",label:"B"},{id:"c",label:"C"},{id:"d",label:"D"}]; selected:"a"; onChosen: function(value) { selected=value } }
''' + controls)

# Exercise the real transport component; only external MPRIS data is stubbed.
shutil.copy2(repo/'TransportPanel.qml',out/'TransportPanel.qml')
shutil.copy2(repo/'ChoiceGroup.qml',out/'ChoiceGroup.qml')
media=(repo/'MediaSession.qml').read_text().replace('import Quickshell.Services.Mpris','').replace('Mpris.players ? Mpris.players.values : []','[]')
(out/'MediaSession.qml').write_text(media)
desktop=(repo/'Desktop.qml').read_text()
# Exercise the shipped action rather than duplicating its palette logic.
color_action=re.search(r'^  function setColorMode\(.*?^  }',
                       (repo/'BarWidget.qml').read_text(),re.M|re.S).group(0).replace('root.','win.')
hover=desktop[desktop.index('  // Keyboard access'):desktop.index('  Column {',desktop.index('  // Keyboard access'))]
controls=desktop[desktop.index('  TransportPanel {'):desktop.index('  Settings {')].replace('id: trayBox','id: trayBox; objectName:"tray"')
start=desktop.index('      Loader {', desktop.index('// One active instance'))
viewport=desktop[start:desktop.index('      Component {',start)].replace('id: vizLoader', 'id: vizLoader; objectName: "viewport"')
backdrop_start=desktop.index('      Loader {',desktop.index('// FastBlur caches:'))
backdrop=desktop[backdrop_start:desktop.index('      // Cover-derived',backdrop_start)]
backdrop=backdrop.replace('id: artBackdrop','id: artBackdrop; objectName: "artworkBackdrop"')
(out/'desktop.qml').write_text("""import QtQuick
import "ModelStore.js" as Store
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
Rectangle {
 id: win; width:600; height:200; color:"#0c0c12"
 property var vizConfig: ({visual:"Siri",enabled:true})
 Component { id:canvasComp; Item {} }
 property Item contentItem: win
 property bool closed:false
 property QtObject firstPlayer: QtObject {
   property bool canControl:true
   property bool canPlay:true
   property bool canPause:true
   property bool canTogglePlaying:true
   property bool canGoPrevious:true
   property bool canGoNext:true
   property bool isPlaying:true
   property string trackTitle:"Blue in Green"
   property string trackAlbum:"Kind of Blue (Legacy Edition)"
   property string trackArtist:"Miles Davis"
   property string trackArtUrl: win.trackArt
   property string identity:"Test player"
   property int previousCount:0
   property int nextCount:0
   function previous() { previousCount++ }
   function next() { nextCount++ }
   function play() { isPlaying=true }
   function pause() { isPlaying=false }
   function togglePlaying() { isPlaying=!isPlaying }
 }
 property QtObject secondPlayer: QtObject {
   property bool isPlaying:false
   property string trackTitle:"Other track"
   property string trackArtist:"Other artist"
   property string identity:"Other player"
 }
 MediaSession { id:media; players:[win.firstPlayer,win.secondPlayer] }
 readonly property var activePlayer: media.player
 QtObject { id:bridge; property string status:"Listening" }
 property string trackArt:"""+repr((repo/'preview.png').as_uri())+"""
 readonly property bool hasArt: trackArt !== "" && vizConfig.artwork !== false
 readonly property bool immersiveArt: false
 property string modeName:"Omaviz"
 function setDesktopActive(v) { closed=!v }
 Timer { id:closeTimer }
"""+color_action+"""
 property string configText: ""
 function selectTestVisual(mode) {
   configText=Store.selectVisual(configText,mode)
   vizConfig=Store.readConfigFromText(configText)
 }
 function writeVizMap(options) {
   configText=Store.patchSettings(configText,"desktop",options)
   vizConfig=Store.readConfigFromText(configText)
 }
"""+backdrop+viewport+hover+controls+'}')

# Load the full production panel, with shell-only hosting and rendering stubbed.
ui=out/'qs'/'Ui'; ui.mkdir(parents=True,exist_ok=True)
ui_types={
'Panel': 'Item { property var bar:null; property string moduleName:""; property string ipcTarget:""; property bool manageIpc:false; property bool opened:true; function close(){opened=false} }',
'KeyboardPanel': 'Item { property var anchorItem; property var owner; property var bar; property bool open:true; property bool centerOnBar:false; property int padding:8; property var focusTarget; property real contentWidth:560; property real contentHeight:700; width:contentWidth; height:contentHeight; function fittedContentWidth(n){return Math.min(560,n)} function fittedContentHeight(n){return Math.min(720,n)} }',
'PanelKeyCatcher': 'Item { signal closeRequested() }',
'PanelSectionHeader': 'Text { color:"#a6afbe"; font.pixelSize:11 }',
'PanelSeparator': 'Rectangle { width:parent.width; height:1; color:"#30333a" }',
'BorderSurface': 'Rectangle { property var borderSpec; color:"#171b22"; radius:6 }',
'ToggleSwitch': 'Item { property int trackHeight:22; property int cursorPad:6; property bool hasCursor:false; property bool cursorRing:false; property color foreground:"white"; property color accent:"blue"; property bool checked:false; signal toggled(); implicitWidth:42; implicitHeight:24; Rectangle { anchors.fill:parent; radius:12; color:parent.checked?"#6095b8":"#303844" } }',
'Toggle': 'Item { property bool hasCursor:false; property color foreground:"white"; property color accent:"blue"; property string label:""; property string description:""; property bool checked:false; signal clicked(); implicitHeight:44; Text {text:parent.label;color:"white"} MouseArea {anchors.fill:parent;onClicked:parent.clicked()} }'
}
for name,body in ui_types.items(): (ui/(name+'.qml')).write_text('import QtQuick\n'+body)
(ui/'qmldir').write_text('module qs.Ui\n'+''.join(f'{name} 1.0 {name}.qml\n' for name in ui_types))
style=(commons/'Style.qml').read_text().replace('bodySmall:12','bodySmall:12,caption:11,title:17').replace('md:6','md:6,popupPadding:8,huge:20,rowPaddingX:8')
style=style.replace('property int cornerRadius:', 'function controlFill() { return "#202530" } property int cornerRadius:')
(commons/'Style.qml').write_text(style)
for name in ['ModelStore.js','DotsCanvas.qml','manifest.json']: shutil.copy2(repo/name,out/name)
full_panel=(repo/'Panel.qml').read_text().replace('import Quickshell\n','').replace('import Quickshell.Io\n','')
a=full_panel.index('  FileView {'); b=full_panel.index('  // Panel foreground',a)
full_panel=full_panel[:a]+full_panel[b:]
(out/'AppPanel.qml').write_text(full_panel)
# Retain bindings and sizing without creating a second GPU fixture in software tests.
import re
visual=(repo/'VisualCanvas.qml').read_text()
props=re.findall(r'^  property (?:bool|int|real|string|color|var) (\w+):',visual,re.M)
(out/'VisualCanvas.qml').write_text('import QtQuick\nItem {\n'+''.join('property var '+p+'\n' for p in props)+'}')
(out/'panel.qml').write_text('''import QtQuick
import "ModelStore.js" as Store
Rectangle {
 width:600; height:760; color:"#11151b"
 QtObject {
  id:host
  property string document:Store.toTOML(Store.defaultConfig())
  property var config:Store.readConfigFromText(document)
  property string settingsError:""
  property string sourceLabel:"PipeWire · Listening"
  property var artworkPalette:[]
  property var spectrumBands:[]
  property bool spectrumSilent:true
  property var spectrumWave:[]
  property real spectrumWaveRms:0
  property int spectrumWaveSerial:0
  property string spectrumBandLayout:""
  property real barGap:1
  function writeVizOption(k,v){var values={};values[k]=v;document=Store.patchSettings(document,"desktop",values)}
  function writeVizOptions(k,v,k2,v2){var values={};values[k]=v;values[k2]=v2;document=Store.patchSettings(document,"desktop",values)}
  function setShuffle(v){document=Store.setShuffle(document,v)}
  function selectGroup(g){document=Store.selectGroup(document,g)}
  function selectVisual(v){document=Store.selectVisual(document,v)}
 }
 AppPanel { objectName:"fullpanel"; x:20;y:20;hostWidget:host }
}
''')
