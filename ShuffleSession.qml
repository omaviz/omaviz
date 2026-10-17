import QtQuick

Item {
  id: session
  property bool active: false
  property var player: null
  // Metadata fallback covers players that omit a stable MPRIS track ID.
  readonly property string trackKey: player && (player.trackTitle || player.trackArtist)
    ? JSON.stringify(player.uniqueId ? [player.identity || "", player.uniqueId]
                      : [player.identity || "", player.trackTitle || "", player.trackArtist || ""]) : ""
  property string lastTrack: ""
  property var lastPlayer: null
  signal trackChanged()
  function seed() { settle.stop(); lastPlayer = player; lastTrack = trackKey }
  onActiveChanged: seed()
  onPlayerChanged: { settle.stop(); Qt.callLater(seed) }
  onTrackKeyChanged: if (active) settle.restart()
  Timer {
    id: settle
    interval: 500
    onTriggered: {
      if (!session.active || !session.trackKey) return
      if (session.lastPlayer !== session.player || !session.lastTrack) { session.seed(); return }
      if (session.trackKey === session.lastTrack) return
      session.lastTrack = session.trackKey
      session.trackChanged()
    }
  }
  Component.onCompleted: seed()
}
