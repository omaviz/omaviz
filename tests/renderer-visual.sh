#!/usr/bin/env bash
# Explicit native/display test; every probe closes within three seconds.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
probe=${1:?Pass the built omaviz-render-probe executable}
artifacts=$(mktemp -d /tmp/omaviz-render-test.XXXXXX)
for mode in Bars Waves Strings Siri Siri-to-Strings Strings-to-Bars; do
  initial=${mode%%-to-*}
  target=${mode##*-to-}
  cat > "$artifacts/$mode.qml" <<QML
import QtQuick
import "file:$repo" as O
Rectangle {
  width: 640; height: 240; color: "black"
  O.VisualCanvas {
    anchors.fill: parent; visual: "$initial"; silent: false
    // Deliberately start without bands to exercise first-frame initialization.
    id: canvas
    wave: { let a=[]; for(let i=0;i<128;i++) a.push(.07*Math.sin(i*.14)); return a }
  }
  Timer { interval: 150; running:true; onTriggered: { canvas.visual="$target"; canvas.bands=[.2,.4,.7,.5,.3,.6,.8,.4] } }
}
QML
  OMAVIZ_PROBE_TIMESTAMPS=0 timeout 6 "$probe" "$artifacts/$mode.qml" "$artifacts/$mode.png" 3 > "$artifacts/$mode.log" 2>&1
  # There must be visible, saturated pixels on the black canvas. This caught
  # the empty-node Spectrum bug that source/unit tests could not detect.
  coverage=$(magick "$artifacts/$mode.png" -colorspace HSL -channel G -separate +channel -threshold 10% -format '%[fx:mean]' info:)
  awk -v coverage="$coverage" 'BEGIN { exit !(coverage > .005) }'
  if rg -q 'Error:|Type .* unavailable|ReferenceError' "$artifacts/$mode.log"; then
    cat "$artifacts/$mode.log"
    exit 1
  fi
  echo "$mode: visible color coverage $coverage"
done
echo "Native captures: $artifacts"
