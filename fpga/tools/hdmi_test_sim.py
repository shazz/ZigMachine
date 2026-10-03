"""Simulate the HDMI test pattern (rtl/board/hdmi_pattern.v) before the board:
CXXRTL of the pattern + zm_vtiming, the checks of tests/tb/hdmi_pattern_tb.cpp,
and frames 0 and N written as PNGs to build/hdmi_test/ to look at.

    uv run python tools/hdmi_test_sim.py [N]    # make -C fpga hdmi-test-sim
"""

import struct
import subprocess
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.test_rtl import RTL_TESTS, _compile_and_run, _cxxrtl  # noqa: E402  (after the path insert)

FPGA = Path(__file__).resolve().parent.parent
OUT = FPGA / "build" / "hdmi_test"


def ppm_to_png(ppm: Path, png: Path) -> None:
    """A binary P6 PPM (as the testbench writes it) to an RGB PNG, stdlib only."""
    data = ppm.read_bytes()
    magic, dims, maxval, pixels = data.split(b"\n", 3)
    if magic != b"P6" or maxval != b"255":
        raise ValueError(f"{ppm}: not an 8-bit P6 PPM")
    w, h = (int(v) for v in dims.split())
    rows = b"".join(b"\x00" + pixels[y * w * 3 : (y + 1) * w * 3] for y in range(h))

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def main(last: int) -> int:
    sources, tb = next((s, t) for top, s, t in RTL_TESTS if top == "hdmi_pattern")
    OUT.mkdir(parents=True, exist_ok=True)
    cc = _cxxrtl("hdmi_pattern", sources, build=OUT)
    exe = cc.parent / "hdmi_pattern_tb"
    run = _compile_and_run("hdmi_pattern", cc, tb)  # the checks over frames 0 and 1
    print(run.stdout, end="")
    if run.returncode != 0:
        return run.returncode
    dump = subprocess.run([str(exe), str(OUT), str(last)], capture_output=True, text=True, check=False)
    print(dump.stdout, end="")
    if dump.returncode != 0:
        return dump.returncode
    for n in (0, last):
        ppm = OUT / f"frame_{n}.ppm"
        ppm_to_png(ppm, OUT / f"frame_{n}.png")
        ppm.unlink()
        print(f"hdmi-test-sim: {OUT / f'frame_{n}.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(int(sys.argv[1]) if len(sys.argv) > 1 else 60))
