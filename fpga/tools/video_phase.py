"""Where a FRESCO pass's clocks go, on a recorded frame (tests/tb/video_phase_tb.cpp).

    uv run python tools/video_phase.py union_main 300 [--timing 0] [--fuse] [--line-major [--nopfb]]

Records the frame first if build/vdump/<tag>/frames lacks it (tools/video_dump.py), builds the
phase testbench against rtl/video, and prints the frame's comp clocks by pass phase. The compute
phases (fill, paint, mix) are the RTL's own; the row I/O (load, fetch, store) is the testbench
memory's (a beat a comp clock), a floor under the board's: the board's row costs are VCAL's.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import video_dump
import video_mix
import video_rtl

FPGA = Path(__file__).resolve().parent.parent
TB = FPGA / "tests" / "tb" / "video_phase_tb.cpp"
WORK = FPGA / "build" / "phase"


def build() -> Path:
    cc = video_rtl.cxxrtl(video_rtl.RTL, WORK)
    exe = WORK / "video_phase_tb"
    if exe.exists() and exe.stat().st_mtime > max(cc.stat().st_mtime, TB.stat().st_mtime):
        return exe
    video_dump.memmap_header()
    inc = [f"-I{video_rtl.CXXRTL_INCLUDE}", f"-I{WORK}", f"-I{video_dump.OUT}", f"-I{TB.parent}"]
    subprocess.run(["clang++", "-std=c++17", "-O2", *inc, str(TB), "-o", str(exe)], check=True)
    return exe


def main(args: list[str]) -> int:
    flags = [a for a in args if a.startswith("--")]
    rest = [a for a in args if not a.startswith("--")]
    if "--timing" in flags:
        flags.insert(flags.index("--timing") + 1, rest.pop(2))
    if len(rest) != 2:
        sys.exit(__doc__)
    tag, frame = rest[0], int(rest[1])
    frames = video_dump.OUT / tag / "frames"
    if not (frames / f"f{frame}.rec").exists():
        video_dump.dump(tag, [frame])
    video_mix.mix(frames, [frame])
    out = subprocess.run([str(build()), *flags, str(frames), str(frame)], capture_output=True, text=True, check=False)
    print(out.stdout, end="", file=sys.stdout)
    print(out.stderr, end="", file=sys.stderr)
    return out.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
