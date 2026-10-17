# v8.10.1 marketplace review evidence

This update combines the v8.10.0 visualization/UI changes, refreshed live previews,
and the fixes below in one proposed verification target. Submit the full merged
master commit after review; neither a PR head nor the previous v8.10.0 commit
includes this combined state. Marketplace approval remains with its maintainers.

## Compressed artwork metadata (#11183)

[Review finding](https://github.com/omacom/omarchy-plugin-marketplace/issues/11183#issuecomment-6207958245):
the transfer cap and 48px scaling did not limit aggregate decompressed PNG metadata
inside the shared shell.

`renderer/artworkpalette.cpp` now checks PNG chunk framing before constructing
QImageReader. It retains only IHDR, PLTE, IDAT, IEND, and bounded transparency data.
Text, compressed ICC profiles, and other ancillary metadata never reach Qt/libpng,
including metadata following IDAT. Unknown critical chunks and malformed/truncated
containers fail closed. No metadata decompression is needed to discard it.

Input is limited to 12 MiB, 4,194,304 pixels, and 8,192 pixels per dimension.
Only PNG/JPEG/WebP raster handlers are selected explicitly. Requests have a
bounded reply buffer, transfer timeout, and absolute ten-second deadline.
Unsupported or oversized artwork falls back to existing placeholders/colors.
The host shell's global QImageReader allocation setting is unchanged.

The decoder reduces the image to at most 192×192 and copies only pixels into a
fresh image. Palette extraction, poster display, and backdrop display reuse that
result. `ArtworkColors.qml` exposes the generated thumbnail data URL; neither
Desktop nor TransportPanel passes a media-supplied original URL to QML Image.
Cancellation/source changes clear both colors and the thumbnail.

Evidence:

- `renderer/artworkpalette_test.cpp` constructs repeated compressed zTXt/iTXt/iCCP
  chunks before and after pixel data with aggregate expansion over 1 GiB. A child
  process must decode the pixels within five seconds and a 256 MiB address-space
  limit. Normal PNG/JPEG, malformed/oversized inputs, safe thumbnail output,
  cancellation, and unchanged global limits are also checked.
- `tests/artwork-backdrop.cjs` renders the production backdrop through the real
  native safe-thumbnail path, then verifies every cached artwork pixel disappears
  when switching from Artwork to Theme.
- Native transport tests cover artwork/details layout and the deselection action.

These checks bound this input path; they are not an audit of Qt or its codecs.

## Earlier metadata and clipboard findings

Track, artist, album, and identity Text items remain PlainText. The full-metadata
tooltip now also supplies an explicit PlainText content item. Only fixed,
repository-authored credit links use styled text. The native interaction harness
checks the tooltip text format.

Hex colors still use bounded key handling with no TextInput/TextEdit, clipboard
read, paste, or input-method commit path. Existing tests deliver a 1 MiB clipboard
value and verify it cannot change the control. See [v8.8.0 evidence](REVIEW-8.8.0.md).

## Preview provenance

`preview.png` shows ten visualization modes, three extra Spectrum/Siri styles,
the real mini, and the current settings panel. Each visualization uses production
VisualCanvas/native rendering with live PipeWire system audio, not a generated
audio fixture. `tools/capture-preview.py` requires an audible PipeWire stream and
records source, timestamp, dimensions, audible frames, options, and renderer digest
in `docs/screenshots/marketing/captures.json`. Bar/settings are actual grim captures,
tightly cropped to exclude surrounding applications. No audio or player metadata
is recorded in these assets.

Layout references were inspected on the marketplace: [OmaSwiss](https://plugins.omarchy.org/plugin.html?id=glasschan.oma-swiss)
for clear hierarchy with real UI, and [Glass Dock](https://plugins.omarchy.org/plugin.html?id=io.github.jeocrypto.glass-dock)
for a focused product hero. Their artwork is not included in Omaviz. The Milky Way
asset retains its [ESO/S. Brunier attribution and CC BY 4.0 license](../renderer/textures/ATTRIBUTION.md).

## Capability scope

The older root-level AGENTS.md finding remains resolved: development instructions
are under `docs/`, and marketplace preflight rejects a root AGENTS.md. The previous
installer findings remain covered by 97 checks against the real install/uninstall
scripts: unowned files and launchers survive, marker traversal is rejected, linked
path components cannot cross the ownership boundary, and uninstall removes only
managed files. No installer behavior changes in this follow-up.

Earlier capability and metadata corrections were [accepted in #10163](https://github.com/omacom/omarchy-plugin-marketplace/issues/10163#issuecomment-6004167825).
Fresh review still applies to the new exact commit; the earlier acceptance is not
treated as approval of this update.

The Rust source and engine binary remain identical to v8.9.1. The native renderer
is rebuilt and its source stamp is verified; this is a freshness check, not a
reproducibility attestation. Native sources and tests are included. HTTP/HTTPS
artwork fetches are documented; audio remains local. The optional installer and
developer container/package-management capabilities remain documented for manual
review, and the standard marketplace installation does not execute install.sh.
