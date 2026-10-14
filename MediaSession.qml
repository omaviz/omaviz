import QtQuick
import Quickshell.Services.Mpris

Item {
  id: session
  property var players: Mpris.players ? Mpris.players.values : []
  property var preferredPlayer: null
  readonly property var player: {
    if (preferredPlayer && players.indexOf(preferredPlayer) >= 0) return preferredPlayer
    var fallback = null
    for (var i = 0; i < players.length; ++i) {
      var p = players[i]
      if (!p) continue
      if (p.isPlaying && (p.trackTitle || p.trackArtist)) return p
      if (!fallback && (p.trackTitle || p.trackArtist || p.identity || p.desktopEntry)) fallback = p
    }
    return fallback
  }
  function toggle() {
    if (!player || !player.canControl) return
    preferredPlayer = player
    if (player.isPlaying && player.canPause) player.pause()
    else if (!player.isPlaying && player.canPlay) player.play()
    else if (player.canTogglePlaying) player.togglePlaying()
  }
  function previous() {
    if (player && player.canControl && player.canGoPrevious) { preferredPlayer = player; player.previous() }
  }
  function next() {
    if (player && player.canControl && player.canGoNext) { preferredPlayer = player; player.next() }
  }
}
