"""Build the RTL video testbenches and run them on dumped frames. Shared by
tests/test_rtl_video.py and by hand:

    uv run python tools/video_rtl.py build/vdump/tutorial/frames 300            # the compositor, per pass
    uv run python tools/video_rtl.py --timing 24 build/vdump/tutorial/frames 300 # clocks, 24-clock memory
    uv run python tools/video_rtl.py --out 5:2 build/vdump/tutorial/frames 300  # whole frames on the wire

Yosys CXXRTL (yowasp) turns the RTL into C++, and clang++ links it with a
testbench: tests/tb/video_comp_tb.cpp for zm_video_comp, tests/tb/video_out_tb.cpp
for zm_video_out (compositor + double-buffered picture + scanout fetch + timing,
two clocks). `rtl_dir`
can point at a mutated copy of rtl/video, which is how the break tests prove the
replays can fail.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import video_mix
import yowasp_yosys

FPGA = Path(__file__).resolve().parent.parent
RTL = FPGA / "rtl" / "video"
TB = FPGA / "tests" / "tb" / "video_comp_tb.cpp"
OUT_TB = FPGA / "tests" / "tb" / "video_out_tb.cpp"
CXXRTL_INCLUDE = Path(yowasp_yosys.__file__).parent / "share/include/backends/cxxrtl/runtime"
SOURCES = [
    "zm_video_sdpram.v",
    "zm_video_regs.v",
    "zm_video_fetch.v",
    "zm_video_bg.v",
    "zm_video_paint.v",
    "zm_video_latch.v",
    "zm_video_plane.v",
    "zm_video_planepath.v",
    "zm_video_mix.v",
    "zm_video_rowio.v",
    "zm_video_pass.v",
    "zm_video_comp.v",
]
OUT_SOURCES = [
    *SOURCES,
    "zm_video_dcram.v",
    "zm_video_scanfetch.v",
    "zm_vtiming.v",
    "zm_video_sync.v",
    "zm_video_scan.v",
    "zm_video_out.v",
]


def cxxrtl(rtl_dir: Path, out_dir: Path, top: str = "zm_video_comp", sources: list[str] = SOURCES) -> Path:
    """`top` as CXXRTL C++ in out_dir/<top>.cc."""
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{top}.cc"
    reads = " ".join(str(rtl_dir / s) for s in sources)
    script = f"read_verilog -I{FPGA / 'gen'} -I{rtl_dir} {reads}; hierarchy -check -top {top}; proc; write_cxxrtl {out}"
    if yowasp_yosys.run_yosys(["-q", "-p", script]) != 0:
        raise RuntimeError(f"yosys failed on {rtl_dir}")
    return out


def build_tb(rtl_dir: Path = RTL, out_dir: Path = FPGA / "build" / "tests", out: bool = False) -> Path:
    """The replay testbench (`out`: the whole-frame one) linked against the RTL in
    rtl_dir, as out_dir/video_comp_tb (video_out_tb).

    It is built in a private directory and renamed into place, because two pytest
    sessions can build it at once (`make test` collects this test file too), and
    neither may exec or compile against the other's half-written files.
    """
    tb, top, sources = (OUT_TB, "zm_video_out", OUT_SOURCES) if out else (TB, "zm_video_comp", SOURCES)
    work = out_dir / f".build-{os.getpid()}-{top}"
    cc = cxxrtl(rtl_dir, work, top, sources)
    inc = [f"-I{CXXRTL_INCLUDE}", f"-I{cc.parent}", f"-I{FPGA / 'build' / 'vdump'}", f"-I{TB.parent}"]
    subprocess.run(["clang++", "-std=c++17", "-O2", *inc, str(tb), "-o", str(work / "tb")], check=True)
    exe = out_dir / tb.stem
    os.replace(work / "tb", exe)
    shutil.rmtree(work)
    return exe


def replay(
    exe: Path, frames_dir: Path, frames: list[int], timing: int | None = None
) -> subprocess.CompletedProcess[str]:
    """Run the testbench; returncode 0 means every pixel of every pass, and of the
    browser's picture (written first by tools/video_mix.py), matched. `timing`:
    serve memory with that first-beat latency and no stalls, and skip the
    per-pass read-back (the clock figures)."""
    video_mix.mix(frames_dir, frames)
    args = [str(exe), *(["--timing", str(timing)] if timing is not None else []), str(frames_dir), *map(str, frames)]
    return subprocess.run(args, capture_output=True, text=True, timeout=1200, check=False)


def wire(
    exe: Path, ratio: tuple[int, int], frames_dir: Path, frames: list[int], starve: int = 1
) -> subprocess.CompletedProcess[str]:
    """Run the whole-frame testbench with the compositor clocked at ratio[0]/ratio[1]
    times the pixel clock; returncode 0 means every pixel and sync on the wire matched.
    `starve`: the scanout fetch gets a beat at most every that many clocks."""
    video_mix.mix(frames_dir, frames)
    args = [str(exe), *(["--starve", str(starve)] if starve > 1 else []), str(ratio[0]), str(ratio[1])]
    args += [str(frames_dir), *map(str, frames)]
    return subprocess.run(args, capture_output=True, text=True, timeout=1200, check=False)


def main(args: list[str]) -> int:
    timing, ratio = None, None
    if "--out" in args:
        at = args.index("--out")
        num, den = args[at + 1].split(":")
        ratio, args = (int(num), int(den)), args[:at] + args[at + 2 :]
    if "--timing" in args:
        at = args.index("--timing")
        timing, args = int(args[at + 1]), args[:at] + args[at + 2 :]
    if len(args) < 2:
        sys.exit("usage: video_rtl.py [--timing LAT | --out C:P] <frames dir> <frame>...")
    d, frames = Path(args[0]), [int(f) for f in args[1:]]
    if ratio:
        result = wire(build_tb(out=True), ratio, d, frames)
    else:
        result = replay(build_tb(), d, frames, timing)
    print(result.stdout, end="")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
