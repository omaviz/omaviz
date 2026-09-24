#!/usr/bin/env bash
# Verify that bin/omaviz-engine is byte-identically reproducible from source.
#
# Reproduces exactly what .github/workflows/repro-build.yml does on CI, but
# locally. Requires only Docker (or any OCI runtime). No Rust toolchain.
#
# Usage:  tools/repro/verify.sh          # verify committed binary
#         tools/repro/verify.sh --build  # also rebuild bin/omaviz-engine
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Digest-pinned — keep in sync with .github/workflows/repro-build.yml
IMAGE="rust@sha256:f47a8de237dcbb0b0ce1099901e60a89728e3d51f24e664b40e947171538ade7"

echo "== omaviz-engine reproducibility check =="
echo "container: $IMAGE"
echo

docker run --rm -i \
  -v "$SRC:/src" \
  -w /src/engine \
  "$IMAGE" \
  bash -euo pipefail -c '
    echo "-- building from source (locked) --"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
      libpipewire-0.3-dev libclang-dev clang pkg-config > /dev/null
    cargo build --release --locked

    echo
    echo "-- SHA256 of fresh build --"
    sha256sum target/release/omaviz-engine
  '

echo
echo "-- SHA256 of committed bin/omaviz-engine --"
sha256sum "$SRC/bin/omaviz-engine"

echo
if [ "${1:-}" = "--build" ]; then
  echo "Copying fresh build into bin/ (rebuild mode)"
  cp "$SRC/engine/target/release/omaviz-engine" "$SRC/bin/omaviz-engine"
  echo "Done — commit bin/omaviz-engine together with your source change."
  exit 0
fi

BUILT_SHA="$(sha256sum "$SRC/engine/target/release/omaviz-engine" | awk '{print $1}')"
COMMITTED_SHA="$(sha256sum "$SRC/bin/omaviz-engine" | awk '{print $1}')"
if [ "$BUILT_SHA" = "$COMMITTED_SHA" ]; then
  echo "PASS: committed binary is byte-identical to the pinned-container build"
else
  echo "FAIL: digests differ — rebuild with: tools/repro/verify.sh --build"
  exit 1
fi
