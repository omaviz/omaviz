import QtQuick
import "native" as Native

Item {
  id: root
  property bool active: false
  MediaSession { id: media }
  property var player: media.player
  readonly property string artUrl: player ? (player.trackArtUrl || "") : ""
  readonly property var colors: extractor.colors
  Native.ArtworkPalette {
    id: extractor
    source: root.active ? root.artUrl : ""
  }
}
