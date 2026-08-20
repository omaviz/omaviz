# ADR-0009: Detached desktop window blank + no audio (T-015) — dual-capture + bands-binding

| | |
|---|---|
| **Status** | Accepted (to implement in v7.6.x) |
| **Date** | 2026-08-19 |
| **Author** | architect (@architect) |
| **Task** | T-015 (roadmap #21) |
| **Applies to** | `plugin/Desktop.qml` (engine spawn + bands Binding), `engine/src/source/pipewire.rs` (node name / autoconnect), `engine/src/main.rs` (per-instance source) |
| **Supersedes** | none |
| **Superseded by** | none |

## 1. Context

The detached desktop window (`Desktop.qml`, current @33c5850, NOT stale) shows the
title "Wave" (correct — `visualName` resolved at Desktop.qml:26-28) but renders an
**empty canvas and shows no audio reaction**. The window spawns its **own**
`omaviz-engine` instance:

```qml
// Desktop.qml:30-53
Process {
  id: bridge
  command: [Model.engineBin, "--bands", String((win.config && win.config.density) || 128)]
  ...
}
```

The mini's shared engine (BarWidget.spectrumProc) works, so the question is
whether the *second* engine captures system audio, and whether the bands it
produces reach the GL renderer. **This is the leading hypothesis for T-015 and
must be confirmed on the live shell (per ADR-0006 §3).** The blank canvas could
also be the bands→GL binding (§2.2); both are covered by the ADR-0006
integration test gate. Note: T-018 ("window never maps") is reclassified as a
layer-shell measurement artifact (user sees the window) — the real defect is
this content/audio one.

## 2. Root cause

### 2.1 Primary — second PipeWire capture gets silence / no stream
The engine's PipeWire backend (`engine/src/source/pipewire.rs`) registers with a
**hard-coded node name** and relies on session-manager autoconnect:
```rust
props.insert(*pw::keys::NODE_NAME, "omaviz-engine");   // SAME name for every instance
props.insert(*pw::keys::STREAM_CAPTURE_SINK, "true");
stream.connect(..., StreamFlags::AUTOCONNECT | ...);
```
When the **mini engine already holds `NODE_NAME = "omaviz-engine"`** and the
detached window launches a *second* `omaviz-engine` process (a separate Quickshell
process), PipeWire sees a duplicate node name. The session manager frequently
fails to autoconnect the second capture stream (or links it to a null/quiet node),
so `bridge.stdout` never emits non-silent frames → `win.spectrumBands` stays
`[]`/silent → the GL renderer draws nothing. The engine only `eprintln!`s capture
errors (pipewire.rs:141), which the desktop window **discards** (Desktop.qml
`bridge.stdout` has no stderr handling), so the silence is invisible.

Additionally, the desktop engine is launched with **only `--bands`**, so
`--source` defaults to `auto` → PipeWire (correct), but there is no per-instance
identity, making the duplicate-name collision the dominant failure.

### 2.2 Secondary — bands → GL binding is fragile
```qml
// Desktop.qml:84-85
Binding { when: desktopViz.item; target: desktopViz.item; property: "bands"; value: win.spectrumBands }
Binding { when: desktopViz.item; target: desktopViz.item; property: "silent"; value: win.spectrumSilent }
```
This binds `bands` *once* when `desktopViz.item` becomes non-null. It does update
on `win.spectrumBands` reassignment in principle, **but** if the `Loader` reloads
the item (e.g. a `gpu` toggle swaps `VisualCanvasGL.qml` ↔ `VisualCanvas.qml`),
the `when` guard goes false then true and the binding re-applies from the *current*
`win.spectrumBands` — which, combined with 2.1 (silence), means even a good frame
can be missed. Settings are pushed via `pushSettings()` (Desktop.qml:101-117), but
that function sets `visual`/`density`/`fire`/etc. and **not** `bands`/`silent` —
so the Binding is the *only* path for live data, and it is one-shot per item
lifetime. Robustness: push live bands on every parsed frame, not via a single
Binding.

## 3. Decision — the fix (spec for dev)

### 3.1 Unique per-instance PipeWire identity (engine)
In `pipewire.rs`, derive the node name from a per-instance id so two engines do
not collide:
```rust
// e.g. append a short pid/instance suffix
let suffix = std::process::id();
props.insert(*pw::keys::NODE_NAME, format!("omaviz-engine-{}", suffix));
```
and/or explicitly target the default sink monitor so autoconnect is unambiguous.
This lets the detached window's engine reliably tap the same monitor the mini uses.
No engine CLI change needed for the desktop spawn (it already passes only
`--bands`; `auto` → PipeWire).

### 3.2 Surface engine diagnostics in the desktop window
Forward `bridge` stderr to the window (or a visible log line) so a capture
failure is diagnosable instead of silent. At minimum, log `bridge` exit/error so
the user sees "no audio source" rather than a blank canvas.

### 3.3 Harden bands → GL delivery (Desktop.qml)
Replace the one-shot `Binding` with an explicit push on every parsed frame:
```qml
stdout: SplitParser {
  onRead: function(data) {
    ... parse obj ...
    win.spectrumBands = obj.bands
    win.spectrumSilent = obj.silent === true
    if (desktopViz.item) {            // push directly, not via fragile Binding
      desktopViz.item.bands = win.spectrumBands
      desktopViz.item.silent = win.spectrumSilent
    }
  }
}
```
(Keep the existing `Binding` as a fallback for item-swap, but the per-frame push
guarantees the GL renderer always has the latest frame.)

### 3.4 No change to the WAVE/GL rendering
`visualName` → GL `visual` mapping is already correct (title "Wave" == GL "Wave").
The blank canvas is a *data* problem (silence/undelivered bands), not a shader
problem.

## 4. Consequences

- **Positive:** the detached window captures system audio independently of the
  mini and renders a live, reacting spectrum (including WAVE). Fixes both
  "blank" and "no audio".
- **Positive:** diagnostics become visible; future capture failures are not
  silent.
- **Negative / cost:** the engine gets a per-instance node name (cosmetic change
  to `pw_dump` output); desktop window gains a small stderr forwarder.
- **Test gate (tester, on live shell — user GPU/UI approval required):**
  Detach → desktop window opens, shows a moving spectrum reacting to playback,
  for Bar/Oscilloscope/**Wave**. Regression: must not require the mini to be
  closed; both engines may run concurrently.

## 5. Rejected alternatives

- **Share the mini's engine output with the desktop window (IPC/socket):** rejected
  — violates the "no socket, no daemon" architecture (APPLICATION_SPEC.md §2); the
  detached window is a separate Quickshell process by design. A second engine is
  correct; it just needs a unique PipeWire identity.
- **Drop the second engine, render desktop from the mini's `spectrumBands`:**
  rejected — cross-process frame sharing would need a socket or file bridge, again
  contradicting Architecture A.

## 6. References
- `plugin/Desktop.qml` — engine `Process` (30-53), bands `Binding` (84-85),
  `pushSettings` (101-117), `visualName` (26-28).
- `engine/src/source/pipewire.rs` — `NODE_NAME` (30), `STREAM_CAPTURE_SINK` (33),
  `AUTOCONNECT` (125), error `eprintln!` (141).
- `engine/src/main.rs` — `source` default `auto` (34-35), `spawn` (52).
- APPLICATION_SPEC.md §2 (Architecture A), §3 (plugin-relative binary), §7
  (detach lifecycle), §13 (#20).
