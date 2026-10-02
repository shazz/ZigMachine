"""Build the RTL video compositor's replay testbench and run it on dumped frames.
Shared by tests/test_rtl_video.py and by hand:

    uv run python tools/video_rtl.py build/vdump/tutorial/frames 300

Yosys CXXRTL (yowasp) turns rtl/video/zm_video_comp.v into C++, and clang++
links it with tests/tb/video_comp_tb.cpp. `rtl_dir` can point at a mutated copy
of rtl/video, which is how the break tests prove the replay can fail.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import yowasp_yosys

FPGA = Path(__file__).resolve().parent.parent
RTL = FPGA / "rtl" / "video"
TB = FPGA / "tests" / "tb" / "video_comp_tb.cpp"
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
    "zm_video_comp.v",
]


def cxxrtl(rtl_dir: Path, out_dir: Path) -> Path:
    """zm_video_comp as CXXRTL C++ in out_dir/zm_video_comp.cc."""
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / "zm_video_comp.cc"
    reads = " ".join(str(rtl_dir / s) for s in SOURCES)
    script = (
        f"read_verilog -I{FPGA / 'gen'} -I{rtl_dir} {reads}; hierarchy -check -top zm_video_comp; "
        f"proc; write_cxxrtl {out}"
    )
    if yowasp_yosys.run_yosys(["-q", "-p", script]) != 0:
        raise RuntimeError(f"yosys failed on {rtl_dir}")
    return out


def build_tb(rtl_dir: Path = RTL, out_dir: Path = FPGA / "build" / "tests") -> Path:
    """The replay testbench linked against the RTL in rtl_dir, as out_dir/video_comp_tb.

    It is built in a private directory and renamed into place, because two pytest
    sessions can build it at once (`make test` collects this test file too), and
    neither may exec or compile against the other's half-written files.
    """
    work = out_dir / f".build-{os.getpid()}"
    cc = cxxrtl(rtl_dir, work)
    inc = [f"-I{CXXRTL_INCLUDE}", f"-I{cc.parent}", f"-I{FPGA / 'build' / 'vdump'}", f"-I{TB.parent}"]
    subprocess.run(["clang++", "-std=c++17", "-O2", *inc, str(TB), "-o", str(work / "tb")], check=True)
    exe = out_dir / "video_comp_tb"
    os.replace(work / "tb", exe)
    shutil.rmtree(work)
    return exe


def replay(exe: Path, frames_dir: Path, frames: list[int]) -> subprocess.CompletedProcess[str]:
    """Run the testbench; returncode 0 means every pixel of every pass matched."""
    args = [str(exe), str(frames_dir), *map(str, frames)]
    return subprocess.run(args, capture_output=True, text=True, timeout=1200, check=False)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: video_rtl.py <frames dir> <frame>...")
    result = replay(build_tb(), Path(sys.argv[1]), [int(f) for f in sys.argv[2:]])
    print(result.stdout, end="")
    sys.exit(result.returncode)
