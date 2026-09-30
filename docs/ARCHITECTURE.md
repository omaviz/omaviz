# Runtime architecture

## Ownership

- `SettingsDocument.qml` owns an observable immutable config snapshot, polled file reader, and the only settings writer. The desktop instance is read-only. `SettingsQueue.js` serializes asynchronous writes and coalesces rapid edits. Failure rolls optimistic state back and exposes an error; no indefinite time-based guard hides disk updates.
- `EngineFeed.qml` owns one process per surface. Changes stop the old process and wait for `exited` before starting the latest command. Disable cancels retries. A bounded start deadline handles executables that fail to start; failure backoff resets only after a validated frame.
- `ModelStore.js` contains pure config/protocol functions. QML bindings observe component properties, never unobservable JS singleton mutations.
- `VisualCanvas.qml` remains the single renderer. `Physics.js` and `Palette.js` are pure computation modules. This refactor does not change frame cadence, physics, gradients, or drawing commands.
- Desktop liveness is a separate short-lived lease. Its writes cannot overwrite settings. The close path keeps its flush delay. Multiple concurrently launched desktop windows still share one lease; concurrent independent desktop sessions are not supported.

## Boundaries and remaining constraints

The TOML reader supports this application's scalar configuration format, not arbitrary TOML documents. Incremental writes preserve unrelated keys/comments. The bar is the sole application settings writer; simultaneous edits by unrelated external programs are not transactional.

File watches are hints; polling remains mandatory (bar 500 ms, desktop 250 ms). Engine inputs are JSON lines with optional metadata. Malformed/nonfinite sample arrays are rejected before rendering.

The installer copies an explicit runtime payload (QML, JS, manifest, assets, engine, optional shaders). Tests, mockups, worktree metadata and build trees are not installed.

## Validation

`npm run verify` exercises config round trips, migrations, queue transitions, palettes, physics, real engine protocol and installer safety, plus Rust tests. Integration tests wait for frame counts with deadlines rather than requiring a loaded CI host to sustain a particular FPS. Spawn failures are explicit failures, not skipped tests or retries that disguise signals.

`npm run test:qml` launches a bounded, software-only Quickshell harness with isolated temporary files. It exercises real settings I/O, scope restart, rapid re-enable, startup failure recovery, and shutdown. Quickshell is required; absence fails explicitly. Run `npm run lint:qml` against the installed Qt environment. Source-string counts, label assertions, indentation-based duplicate detection, and tests of unused store APIs have been removed.

Native integration is a local gate; Ubuntu CI runs the portable suites because it does not provide the host's Quickshell modules. Performance claims require profiling, and visual equivalence requires rendering comparisons; passing unit tests does not establish either.
