# v8.7.0 release review

Reviewed 2026-10-10, including the existing uncommitted renderer and compact-feed work. The release is prepared in an isolated worktree because the original checkout has an unfinished rebase. Local backups are excluded.

## Findings and changes

| Area | Finding and action |
| --- | --- |
| Correctness and recovery | Capture-loss heartbeats cleared bands but retained the last waveform. Clear every feed and preserve Siri/Strings layout markers; add a four-layout regression. |
| Input robustness | Nonfinite PCM could poison FFT/wave output, and manual JSON string escaping missed control characters. Sanitize PCM, guard serialized numeric values, and use serde's string escaping; add unit and executable regressions. |
| State and compatibility | Compact feeds use different band/wave lengths. Extend real QML component tests through Siri, Strings, and full-feed restarts; retain old-frame compatibility, polling, queued writes, and desktop leases. |
| Native rendering | Build all shaders and native tests, exercise mode transitions, and compare CPU/reference and retained paths. Warm up comparison surfaces before their fixed timeline to avoid startup-coalesced submissions. |
| UX and accessibility | Exercise existing native keyboard/mouse controls and desktop proportions. Keep Classic Siri opt-in and preserve ribbon, custom-color, and monochrome behavior. |
| Packaging and portability | Installer allowlist includes all root QML/JS, the engine, and the native module. Existing 88 safety checks pass. Replace the host-linked engine with the exact CI container artifact before release. |
| Supply chain and CI | Add native compilation/CTest to PR and release gates; use locked Cargo builds. Clarify that only the engine has a reproducibility gate and that Debian package repositories are not frozen snapshots. |
| Marketplace | Compare generated fields with the live verification template. Share form generation, submit multiline bodies through stdin, retain exact-commit HEAD checks and duplicate markers. |
| Documentation | Synchronize v8.7.0 metadata, correct the documented default motion, remove the stale current-binary digest assertion, and record 13 durable lessons in docs/AGENTS.md. |

## Acceptance evidence

- JS suites, installer safety checks, 48 Rust tests, and QML lint pass locally.
- Real offscreen QML I/O/process tests cover settings writes, compact feed transitions, failure backoff, and shutdown.
- Native CTest passes both response and artwork suites. Native control tests exercise keyboard/mouse behavior and desktop resizing.
- Eight bounded mode/transition probes render visible content; captured Bars, Waves, Strings, and Siri images were inspected.
- Detailed deterministic parity and final exact-commit CI results are recorded in the release PR before merge.

## Limits and follow-up

The retained Spectrum path remains experimental: prior measurements did not establish a 50% improvement, and retained stack tiles can increase GPU work. Image parity does not establish performance improvement. `OMAVIZ_SPECTRUM_RETAINED=0` remains available.

The committed Qt library is locally built and natively tested; its bytes do not have the engine's reproducibility guarantee. Arch native CI tests source compatibility against current distribution packages.

This review does not claim a formal security audit, exhaustive hardware coverage, or a fresh live PipeWire/server-restart soak test. Tests use controlled audio and bounded native probes. Installer tests use isolated directories; the user's live shell is not restarted. Marketplace approval is external to this release and remains separate from submission.
