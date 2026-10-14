# Runtime architecture

## Ownership

- `SettingsDocument.qml` owns an observable immutable config snapshot, polled file reader, and the only settings writer. The desktop instance is read-only. `SettingsQueue.js` serializes asynchronous writes and coalesces rapid edits. Failure rolls optimistic state back and exposes an error; no indefinite time-based guard hides disk updates.
- `EngineFeed.qml` owns one process per surface. Changes stop the old process and wait for `exited` before starting the latest command. Disable cancels retries. A bounded start deadline handles executables that fail to start; a four-second valid-spectrum watchdog handles live stalls and a 500 ms termination deadline bounds shutdown; failure backoff resets only after a validated frame.
- `ModelStore.js` contains pure config/protocol functions. QML bindings observe component properties, never unobservable JS singleton mutations.
- `VisualCanvas.qml` owns the shared renderer API and physics; `renderer/geometry.cpp` draws native scene-graph geometry on every surface. Desktop waveforms fit a centered 3:1 area.
- Desktop liveness is a separate short-lived lease. Its writes cannot overwrite settings. The close path keeps its flush delay. Multiple concurrently launched desktop windows still share one lease; concurrent independent desktop sessions are not supported.

## Boundaries and remaining constraints

The TOML reader supports this application's scalar configuration format, not arbitrary TOML documents. Incremental writes preserve unrelated keys/comments. The bar is the sole application settings writer; simultaneous edits by unrelated external programs are not transactional.

File watches are hints; polling remains mandatory (bar 500 ms, desktop 250 ms). Engine inputs are JSON lines with optional metadata. Malformed/nonfinite sample arrays are rejected before rendering.

The installer copies an explicit runtime payload (QML, JS, manifest, assets, engine, native renderer, optional shaders). Tests, mockups, worktree metadata and build trees are not installed.

## Validation

`npm run verify` exercises config round trips, migrations, queue transitions, palettes, physics, real engine protocol and installer safety, plus Rust tests. Integration tests wait for frame counts with deadlines rather than requiring a loaded CI host to sustain a particular FPS. Spawn failures are explicit failures, not skipped tests or retries that disguise signals.

`npm run test:qml` launches a bounded, software-only Quickshell harness with isolated temporary files. It exercises real settings I/O, scope restart, rapid re-enable, startup failure recovery, and shutdown. Quickshell is required; absence fails explicitly. Run `npm run lint:qml` against the installed Qt environment. `npm run test:interactions` additionally exercises current native controls and desktop resize behavior.

Native integration is a local gate; Ubuntu CI runs the portable suites because it does not provide the host's Quickshell modules. Performance claims require profiling, and visual equivalence requires rendering comparisons; passing unit tests does not establish either.

## Review follow-up

`MediaSession.qml` owns player selection and playback capabilities; `TransportPanel.qml` renders the thumbnail/actions, and `ArtworkColors.qml` accepts the same player. `ChoiceGroup.qml` switches between direct options (<5) and a dropdown. The catalog and pure look transformations live in ModelStore; SettingsDocument.replace queues the entire transformation atomically. The panel uses normal bounded scrolling.

Capture channels remain separate until power averaging in the FFT analyzer. The capture mailbox has a four-chunk limit and evicts oldest audio, while generated/replayed events use bounded backpressure. Display density never changes the frequency axis. Desktop geometry is private UI state in desktop-window.ini, not a second application-settings writer.
