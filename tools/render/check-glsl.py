#!/usr/bin/env python3
"""Validate the GLSL variants Qt bakes for every renderer shader.

qt_add_shaders() bakes GLSL 100 es and 120 variants alongside 150. On an
OpenGL compatibility-profile context (the Omarchy shell on NVIDIA) a legacy
variant is what gets compiled, and SPIR-V-Cross happily emits constructs
those versions do not have (integer %, int clamp/min/max, const arrays).
NVIDIA's compiler then rejects the shader at runtime (e.g. "'%' requires
GL_EXT_gpu_shader4") and the visual draws nothing.

This compiles each shader with qsb and runs the legacy variants through the
Khronos reference compiler, so a construct a strict driver will refuse fails
here instead of on the user's bar.

Usage: tools/render/check-glsl.py [--qsb PATH] [--glslang PATH]
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHADERS = ROOT / "renderer" / "shaders"
# (qsb --glsl argument, header line in `qsb --dump`)
VARIANTS = [("100es", "GLSL 100 es"), ("120", "GLSL 120")]


def find_tool(explicit, names, extra_dirs=()):
    if explicit:
        return explicit
    for name in names:
        found = shutil.which(name)
        if found:
            return found
        for d in extra_dirs:
            p = Path(d) / name
            if p.is_file():
                return str(p)
    return None


def extract(dump, header):
    """Return the source text of the variant whose dump header matches."""
    lines = dump.splitlines()
    for i, line in enumerate(lines):
        # The dump opens with an indented summary of the same headers; the
        # section that carries the source starts unindented.
        if re.match(rf"^Shader \d+: {re.escape(header)} \[Standard\]$", line.rstrip()):
            body = []
            started = False
            for rest in lines[i + 1:]:
                if rest.startswith("Contents:"):
                    started = True
                    continue
                if started:
                    if rest.startswith("*" * 10):
                        break
                    body.append(rest)
            return "\n".join(body).strip() + "\n"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--qsb")
    ap.add_argument("--glslang")
    args = ap.parse_args()
    qsb = find_tool(args.qsb, ["qsb", "qsb6", "qsb-qt6"], ["/usr/lib/qt6/bin", "/usr/lib/x86_64-linux-gnu/qt6/bin"])
    glslang = find_tool(args.glslang, ["glslangValidator", "glslang"])
    if not qsb or not glslang:
        print(f"SKIP: need qsb ({qsb}) and glslangValidator ({glslang})")
        return 0

    failures = 0
    shaders = sorted(p for p in SHADERS.iterdir() if p.suffix in (".vert", ".frag"))
    with tempfile.TemporaryDirectory() as tmp:
        for shader in shaders:
            for arg, header in VARIANTS:
                out = Path(tmp) / f"{shader.name}.{arg}.qsb"
                subprocess.run([qsb, "--glsl", arg, "-o", str(out), str(shader)], check=True,
                               capture_output=True, text=True)
                dump = subprocess.run([qsb, "--dump", str(out)], check=True, capture_output=True, text=True).stdout
                source = extract(dump, header)
                if source is None:
                    print(f"FAIL {shader.name} [{header}]: variant missing from qsb output")
                    failures += 1
                    continue
                src = Path(tmp) / f"{shader.stem}.{arg}{shader.suffix}"
                src.write_text(source)
                # glslang accepts const arrays in 1.20; NVIDIA refuses them ("C7516: OpenGL does not allow
                # constant arrays"). SPIRV-Cross hoists any constant local array to such a global.
                const_arrays = [l.strip() for l in source.splitlines()
                                if re.match(r"^\s*const\s+\w+\s+\w+\s*\[\d*\]\s*=", l)]
                if const_arrays:
                    failures += 1
                    print(f"FAIL {shader.name} [{header}]: const array (rejected by NVIDIA)")
                    for l in const_arrays[:3]:
                        print("   ", l[:100])
                    continue
                r = subprocess.run([glslang, str(src)], capture_output=True, text=True)
                if r.returncode != 0:
                    failures += 1
                    errors = [l for l in r.stdout.splitlines() if "ERROR" in l and "compilation errors" not in l]
                    print(f"FAIL {shader.name} [{header}]")
                    for e in errors[:5]:
                        print("   ", e.replace(str(src), src.name))
                else:
                    print(f"ok   {shader.name} [{header}]")
    if failures:
        print(f"{failures} shader variant(s) would be rejected by a strict GLSL compiler")
        return 1
    print("PASS: every legacy GLSL variant compiles")
    return 0


if __name__ == "__main__":
    sys.exit(main())
