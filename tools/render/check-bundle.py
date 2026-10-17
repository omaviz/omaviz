#!/usr/bin/env python3
"""Catch accidental source/bundle drift. A build stamp is not an attestation."""
import hashlib
from pathlib import Path
root = Path(__file__).resolve().parents[2]
renderer = root / "renderer"
inputs = [p for p in renderer.rglob("*") if p.is_file()
          and "build" not in p.relative_to(renderer).parts
          and (p.suffix in (".cpp", ".h") or any(d in p.relative_to(renderer).parts for d in ("shaders", "textures")))]
inputs.append(renderer / "CMakeLists.txt")
identity = "".join(f"{p.relative_to(renderer).as_posix()}:{hashlib.sha256(p.read_bytes()).hexdigest()}\n"
                   for p in sorted(inputs, key=lambda p: p.relative_to(renderer).as_posix()))
digest = hashlib.sha256(identity.encode()).hexdigest()
marker = f"OMAVIZ_RENDERER_SOURCE:{digest}".encode()
if marker not in (root / "native/libomavizrenderer.so").read_bytes():
    raise SystemExit("Bundled renderer is stale or missing its build stamp. Run ./build.sh before publishing.")
print("PASS: bundled renderer source stamp matches all native source/shader inputs")
