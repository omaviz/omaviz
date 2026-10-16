# v8.9.1 marketplace review evidence

This release adds three visualizations and refreshes the marketplace preview.
It preserves the v8.8.0 clipboard fix and PlainText player metadata handling;
see [the prior review evidence](REVIEW-8.8.0.md) for the original finding and
capability scope. No new installer, network, clipboard, or process-launch path
is introduced by the visualizations.

## Rendering and resource bounds

Bokeh, Pixel Wave, and Orbit share VisualCanvas and one retained native node.
Geometry rebuilds only on mode, size, or pixel-scale changes. The CPU updates
24 frequency envelopes and a 20-column, eight-row history. Vertex/fragment
shaders position and shade the retained primitives. Mini surfaces reduce counts;
silent and hidden surfaces settle and sleep. Existing capture protocols remain
unchanged. APP_SPEC.md records measured CPU/GPU tradeoffs without promising
identical performance on other hardware.

## Compatibility and regression coverage

Release validation includes JS/state/physics/protocol tests, installer safety,
Rust tests, Qt 6 QML lint, real QML component/feed transitions, native controls
(including clipboard and oversized input), native response/artwork tests, and
the renderer source-stamp guard. Native catalog captures cover motion, silence,
resize, original/custom/artwork palettes, and light/dark monochrome. CI builds
the renderer and shaders on Arch and verifies the engine in its pinned container.
Exact-commit CI and release results remain available on the PR/release checks.

## Preview provenance

preview.png is composed from genuine production visualization and UI captures.
All seven visualization frames use live PipeWire system audio. The bar is an
earlier v8.9.1 playback capture; the settings panel is the actual installed UI.
Source PNGs and capture records live in docs/screenshots/marketing/; the layout
can be regenerated with python3 tools/render-preview.py. No generated artwork or
repainted visualization is substituted for the product.

The bundled-binary and optional-installer capabilities remain subject to manual
marketplace review. A passing local or CI check does not imply marketplace approval.
