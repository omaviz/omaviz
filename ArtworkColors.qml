import QtQuick
import "native" as Native

Item {
  id: root
  property bool active: false
  property bool imageActive: false
  MediaSession { id: media }
  property var player: media.player
  readonly property string artUrl: player ? (player.trackArtUrl || "") : ""
  readonly property var colors: extractor.colors
  readonly property url imageSource: extractor.imageSource
  Native.ArtworkPalette {
    id: extractor
    source: root.active || root.imageActive ? root.artUrl : ""
  }
}
