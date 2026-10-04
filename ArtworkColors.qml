import QtQuick
import Quickshell.Services.Mpris
import "native" as Native

Item {
  id: root
  property bool active: false
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: {
    var fallback = null
    for (var i = 0; i < players.length; ++i) {
      var p = players[i]
      if (!p) continue
      if (p.isPlaying && (p.trackTitle || p.trackArtist)) return p
      if (!fallback && (p.trackTitle || p.trackArtist || p.identity || p.desktopEntry)) fallback = p
    }
    return fallback
  }
  readonly property string artUrl: player ? (player.trackArtUrl || "") : ""
  readonly property var colors: extractor.colors
  Native.ArtworkPalette {
    id: extractor
    source: root.active ? root.artUrl : ""
  }
}
