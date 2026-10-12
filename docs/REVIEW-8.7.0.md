# v8.7.0 release review

Reviewed 2026-10-11, including the existing uncommitted renderer and compact-feed work. The release is prepared in an isolated worktree because the original checkout has an unfinished rebase. Local backups are excluded.

## Findings and changes

| Area | Finding and action |
| --- | --- |
| Correctness and recovery | Capture-loss heartbeats cleared bands but retained the last waveform. Clear every feed and preserve Siri/Strings layout markers; add a four-layout regression. |
| Input robustness | Nonfinite PCM could poison FFT/wave output, and manual JSON string escaping missed control characters. Sanitize PCM, guard serialized numeric values, and use serde's string escaping; add unit and executable regressions. |
| State and compatibility | Compact feeds use different band/wave lengths. Extend real QML component tests through Siri, Strings, and full-feed restarts; retain old-frame compatibility, polling, queued writes, and desktop leases. |
| Native rendering | Build all shaders and native tests, exercise mode transitions, and compare CPU/reference and retained paths. Warm up comparison surfaces before their fixed timeline to avoid startup-coalesced submissions. The subsequent UX pass placed independent rotating Strings around a uniform virtual pipe on the full desktop surface and removed vertical gaps from stack rows. |
| UX and accessibility | Exercise existing native keyboard/mouse controls and desktop proportions. Keep Classic Siri opt-in and preserve ribbon, custom-color, and monochrome behavior. Desktop bars grow 50–100% wider in wide windows; leaving Bars unloads the cached artwork backdrop. Correct an undefined panel spacing token found in the installed shell journal. |
| Packaging and portability | Installer allowlist includes all root QML/JS, the engine, and the native module. Existing 88 safety checks pass. Replace the host-linked engine with the exact CI container artifact before release. |
| Supply chain and CI | Add native compilation/CTest to PR and release gates; use locked Cargo builds. Clarify that only the engine has a reproducibility gate and that Debian package repositories are not frozen snapshots. |
| Marketplace | Compare generated fields with the live verification template. Share form generation, submit multiline bodies through stdin, retain exact-commit HEAD checks and duplicate markers. |
| Documentation | Synchronize v8.7.0 metadata, correct the documented default motion, remove the stale current-binary digest assertion, and record 19 durable lessons in docs/AGENTS.md. |

## Acceptance evidence

- All 102 JS tests, 88 installer safety checks, 48 Rust tests, and QML lint pass locally.
- Real offscreen QML I/O/process tests cover settings writes, compact feed transitions, failure backoff, and shutdown.
- Native CTest passes both response and artwork suites. All 21 native control checks pass, covering keyboard/mouse behavior and desktop resizing.
- Eight bounded mode/transition probes render visible content; captured Bars, Waves, Strings, and Siri images were inspected.
- Deterministic parity passes: Siri: 18 cases, maximum normalized RMSE 0.00000492; Strings: 14 cases with phase, audio, and height assertions; Bars: 20 cases, maximum normalized RMSE 0.00010430. All parity errors are below the 0.001 threshold; compact wake/settle checks pass. In the final quiet/loud fixture the pipe grows from 226 to 285 visible pixels.
- Follow-up native comparison and interaction checks cover the artwork fix, bar density, seamless stack rows, and Strings pipe motion; exact-commit CI results are recorded in release PR #29 before merge.

The committed CI engine artifact from run `38094232645` has SHA256
`156ea7d9ef6d61d2e4585fad7c6f71fc8d95f6c5b5990af7d506723399207af4`.
Its source build passed the double-build determinism and binary-match gates.

## Limits and follow-up

The retained Spectrum path remains experimental: prior measurements did not establish a 50% improvement, and retained stack tiles can increase GPU work. Image parity does not establish performance improvement. `OMAVIZ_SPECTRUM_RETAINED=0` remains available.

The committed Qt library is locally built and natively tested; its bytes do not have the engine's reproducibility guarantee. Arch native CI tests source compatibility against current distribution packages.

This review does not claim a formal security audit, exhaustive hardware coverage, or a fresh live PipeWire/server-restart soak test. Tests use controlled audio and bounded native probes. The requested local reinstall was completed; the user's live shell restarted and the installed engine/renderer hashes matched the candidate. Marketplace approval is external to this release and remains separate from submission.
