#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d /tmp/omaviz-controls.XXXXXX)
python "$here/generate.py" "$work/fixture"
cmake -S "$here" -B "$work/build" > "$work/build.log" 2>&1
cmake --build "$work/build" -j2 >> "$work/build.log" 2>&1
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software
"$work/build/controls-test" "$work/fixture"
"$work/build/desktop-controls-test" "$work/fixture"
echo "Interaction artifacts: $work"
