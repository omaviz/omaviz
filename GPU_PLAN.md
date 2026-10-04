# Shared GPU visualization migration

Goal: one renderer for mini, settings preview and desktop, with spectrum,
oscilloscope, flowing layered glowing waves, and reference-inspired Strings. Preserve colors, peak hold,
accelerating fall, settings persistence and desktop lifecycle. Target visibly
paced 60 fps; audio delivery and presented frames must be measured separately.

## Accepted budgets (targets, not measured results)

CPU is total incremental plugin CPU, including engine, with 100% equal to one
logical core. GPU time is incremental visualization work per rendered frame.

| Configuration at 60 fps | CPU | GPU time/frame |
| --- | --- | --- |
| Mini | <=2% | <=0.3 ms |
| Mini + settings preview | <=4% | <=0.7 ms |
| Desktop bars/scope at 1080p | <=5% | <=1 ms |
| Complex desktop effects at 1080p | <=10% | <=3 ms |
| Settled silence | <=0.5% | no continuous visualization draws |

Secondary same-machine GPU utilization targets: mini <2%, desktop bars/scope
<5%, complex effects <20%. Measure enabled-minus-disabled costs, GPU clocks,
power and frame-time spikes. Percentages alone cannot prove GPU efficiency.

## Implementation and acceptance

- VisualCanvas.qml remains the common API and physics owner. A shared native
  Qt Quick geometry item batches drawing for all surfaces; no browser runtime
  or duplicate Canvas/GPU implementations in the shipped product.
- Keep small FFT/physics work on CPU, retain GPU geometry, avoid full-surface
  CPU image uploads. Drive visual motion from the display clock with fixed
  60 Hz physics steps and bounded catch-up.
- Add Waves as an explicit third persisted mode, migrating legacy scope bool.
  Waves are original audio-reactive layered glowing ribbons inspired by the
  requested Plexamp appearance, not a claim of pixel-identical reproduction.
- Preserve native QML controls and crisp edges; pause settled/hidden rendering.
- Package the native module so marketplace users do not build it themselves.
  Document supported Qt/architecture and maintainer build instructions.
- Verify config migration, physics, shader/geometry rendering, all three
  surfaces, silence/resume, resizing, HiDPI, visual colors, and live backend.
- Measure actual frame presentation and CPU/GPU budgets before declaring the
  migration finished. Unmeasured budgets remain outstanding, not passed.
- Defer projectM until MilkDrop preset support is requested.

## Strings reference

The supplied Plexamp screenshot adds a fourth mode: crossing warm gold/cream
strands and defocused pale-blue foreground strings. The amber backdrop is
temporarily omitted at the user's request. Audio waveform samples add local
vibration to each strand, while RMS controls its overall excursion. Its carrier
pattern stays fixed in x, with plucked standing modes instead of lateral
travel. This matches the user's description of Plexamp Strings motion. It uses
the shared native renderer and normal persisted visual setting.
Native visual and performance acceptance remains in progress.

## Measurements on this machine (2026-10-03)

- The installed standalone Desktop now loads the native module and displays
  a window. The installer resolves the native import to the installed file URL;
  Quickshell's virtual QML path had prevented desktop launch.
- Strings at 1920×1080 with generated mixed audio, after standing-motion and
  palette refinement: median frame interval 16.67 ms, 95th percentile
  19.12 ms, renderer process 10.05% of one CPU core plus engine 0.90%, GPU
  95th percentile 0.64 ms. GPU passes the 3 ms complex-effect target; CPU
  slightly exceeds the 10% target in this sample (10.96% total). An earlier
  sample on the same mesh was 9.88% total. More measurement/optimization is
  needed before accepting the CPU budget.
- Live shell Bars: disabled baseline 6.19%; mini plus engine 8.49%
  (increment 2.30%, above 2% target); mini plus settings preview 11.89%
  (increment 5.70%, above 4% target). These are 10-second samples and
  remain performance work, not accepted results.
- Three captured native frames show fixed horizontal wave landmarks while
  their amplitudes vibrate. An earlier installed Strings preview showed live
  audio response. Desktop open, persistence, and current shell import were
  verified before the latest visual refinement. Silence/resume and full
  mode-by-mode budget checks remain open.
