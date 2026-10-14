# v8.8.0 marketplace review evidence

## Clipboard input (review on #11183)

The color control in Panel.qml no longer instantiates TextInput or TextEdit.
Its plain Item handles one hex character per key event and retains at most seven
characters. It does not access QClipboard, clipboard MIME data, canPaste, paste,
or input-method commits. Ctrl+V and Shift+Insert do not read clipboard data.
This applies whether the panel and color section are visible or hidden. The
tradeoff is explicit: hex colors are typed; clipboard paste is unavailable.

Native interaction coverage asserts the absence of QQuickTextInput/QQuickTextEdit
in the color fixture, delivers a 1 MiB clipboard value and IME commit, and checks
that input remains unchanged. Typed valid/invalid colors, Enter, focus loss,
external palette updates and keyboard navigation are also exercised. These
checks test the removal of the read path; they do not claim an audit of Qt.

## Earlier metadata review (#10163)

TransportPanel renders track title, artist and player identity with Text.PlainText.
No external player metadata is interpreted as rich text.

## Declared capabilities

- The bundled Rust engine and Qt native renderer remain necessary runtime binaries.
  Both sources are included. The release workflow requires the engine to match a
  pinned-container rebuild and publishes its digest and provenance attestation.
- Native CI compiles shaders and C++ and runs response/artwork tests. The bundled
  renderer source stamp detects stale inputs; it is not a reproducibility or
  security attestation.
- The standard marketplace path loads the root plugin without install.sh.
  The optional installer writes the documented user plugin and launcher locations;
  uninstall removes only managed files. Existing settings are preserved.
- apt-get in tools/repro/verify.sh runs inside the developer build container. It is
  not invoked by the installed plugin or standard marketplace installation.

## Release behavior

Settings automatically persist per visualization. Save/Restore/Reset and starting
looks are removed. Buttons are square. Original spectrum mapping is restored,
and Stacks has visible segment gaps in both native rendering paths. Live capture
recovery and the bounded audio queue remain enabled.

Screenshots are current native renderer captures using controlled sample data;
the settings capture is the installed release candidate. Marketplace verification
is tied to the submitted full commit SHA and requires maintainer approval.
