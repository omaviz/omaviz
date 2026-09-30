# GPU exploration with unchanged visuals

## What is accelerated today

The existing renderer uses Qt Quick Canvas. Qt 6 paints Canvas into a QImage, then the scene graph composites the texture. On this machine the bounded native probe selected QRhi/OpenGL, the threaded scene-graph loop, and the AMD Radeon Pro 580X (radeonsi). Thus compositing already uses the GPU; the JavaScript drawing and Canvas raster work do not become GPU work because a settings flag is enabled.

The former `gpu` setting had no consumer. The panel now reports the actual compositing API instead of offering an ineffective switch. Legacy config keys remain harmless and preserved by incremental writes. Renderer, physics, palette, paint cadence, and default Canvas strategy are unchanged.

Qt's [Canvas documentation](https://doc.qt.io/qt-6/qml-qtquick-canvas.html) states that Canvas.Image is the supported target and FramebufferObject is ignored in Qt 6. Threaded moves painting work to another CPU thread; it is not a GPU rasterizer.

## Options evaluated

| Option | Likely benefit | Cost / parity risk | Decision |
| --- | --- | --- | --- |
| Automatic Qt scene-graph compositing | Already active on supported hardware | Software fallback remains Qt-owned | Keep |
| Canvas.Threaded | May reduce UI-thread blocking | Same raster/upload work; scheduling/latency needs profiling | Reproducible experiment only |
| Canvas framebuffer target | None in Qt 6 | Ignored setting | Reject |
| Add a shader over the existing Canvas | Effects after rasterization | Still pays Canvas CPU work and texture upload; extra pass | No benefit for unchanged appearance |
| Native QQuickItem + QSGGeometryNode | GPU geometry for bars, peaks, stacks and reflection; avoid full-image uploads | Native Qt/Quickshell packaging, shader materials, exact AA/gradient parity, software fallback | Best candidate for a future measured prototype |
| GPU FFT | Could move DSP arithmetic | Small FFTs plus transfers/synchronization; unrelated to Canvas bottleneck | Profile first; no justification yet |

Qt documents [custom scene-graph geometry/materials and render-thread ownership](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html). A future native implementation should sit behind the existing VisualCanvas interface and reuse Physics/Palette; it must not duplicate physics or introduce a second independent visual design.

## Reproduce the evidence

Requires Node and the same Quickshell/Qt runtime as the app:

```sh
npm run test:render -- --output /tmp/omaviz-render-software
npm run test:render -- --native --output /tmp/omaviz-render-native
```

Each strategy runs in an isolated temporary config under a 12-second timeout. Default mode is offscreen/software. `--native` briefly opens a 320×160 window using the current desktop backend. Neither mode launches Desktop.qml, starts audio, changes user settings, or restarts the shell. Output includes backend logs, PNG exports and report.json. Hardware identity comes from Qt's RHI logs; [GraphicsInfo](https://doc.qt.io/qt-6/qml-qtquick-graphicsinfo.html) identifies the selected API, not whether a driver implements it in hardware.

On 2026-09-30, all eight fixtures (bars, Flame, spikes, stacks, horizontal gradient, mono, reflection/wash, scope) exported byte-identical PNGs between Immediate and Threaded on both software and native OpenGL. Requested strategies were confirmed as 0 and 1 in the logs. Software/native PNG hashes differ because the native output uses the monitor's device-pixel ratio; comparisons are within a backend.

This is static Canvas-output parity, not an FPS benchmark, motion/latency test, or comparison of final compositor screenshots. It does not justify enabling threaded painting by default or claiming a performance improvement.

## Promotion gate for a GPU renderer

Measure CPU and frame timings at mini, preview and desktop sizes using identical input on at least one integrated GPU and one discrete GPU. Compare frozen frames at 1× and fractional scales across all modes, gradients, peaks, silence and reflections; then verify motion timing and input responsiveness. Require software fallback and hot-reload/close recovery. Adopt a native backend only with a measured benefit and approved visual parity. Until then the production renderer remains unchanged.
