#!/usr/bin/env python3
"""omaviz capture relay v2.

Spawns an ffmpeg pulse capture and re-emits its raw f32 stdout as base64
lines (Quickshell DataStreamParser is text-only, so binary cannot cross the
QML boundary directly). QML decodes each line with Qt.atob() and feeds the
bytes to dsp.js.

Usage: capture_relay.py <monitor-source-name>
Exits when stdin/stdout breaks or the child dies; BarWidget restarts us.
"""
import sys, subprocess, base64

CHUNK = 4096

def main():
    if len(sys.argv) < 2:
        print("usage: capture_relay.py <monitor-source>", file=sys.stderr)
        return 2
    monitor = sys.argv[1]
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "pulse", "-i", monitor,
        "-ac", "1", "-ar", "44100",
        "-f", "f32le", "-",
    ]
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    except OSError as e:
        print(f"relay: cannot spawn ffmpeg: {e}", file=sys.stderr)
        return 1
    out = sys.stdout
    try:
        while True:
            b = p.stdout.read(CHUNK)
            if not b:
                break
            out.write(base64.b64encode(b).decode() + "\n")
            out.flush()
    except BrokenPipeError:
        p.terminate()
        return 0
    except KeyboardInterrupt:
        pass
    finally:
        if p.poll() is None:
            p.terminate()
    return 0

if __name__ == "__main__":
    sys.exit(main())
