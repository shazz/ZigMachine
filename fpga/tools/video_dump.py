"""Build and run vdump (tools/video_dump/): the native host plus a recorder that
dumps frames for the RTL compositor's replay testbench (tests/test_rtl_video.py).

    uv run python tools/video_dump.py union_intro 60 120      # -> build/vdump/union_intro/frames/f60.*
    uv run python tools/video_dump.py --synth fullscreen      # -> build/vdump/_synth/fullscreen/f1.*

It reuses the per-cart objects `make host CART=<tag>` leaves in build/host/ and
recompiles only env.c, with the machine's hblDispatch forwarder renamed so that
vdump's own forwarder can bracket each HBL with state records.
"""

import shutil
import subprocess
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
HOST = FPGA / "build" / "host"
OUT = FPGA / "build" / "vdump"
SRC = FPGA / "tools" / "video_dump"
WABT = FPGA / ".tools" / "wabt"
W2C_RT = WABT / "share" / "wabt" / "wasm2c"
COMMON = ["machine.o", "rom.o", "rt.o", "rt-mem.o", "rt-exc.o", "sha256.o"]
# The host's own flags (fpga/Makefile HOST_CFLAGS): the same machine must run.
CFLAGS = [
    "-std=c11",
    "-D_POSIX_C_SOURCE=200809L",
    "-O2",
    "-ffp-contract=off",
    "-w",
    "-DWASM_RT_USE_MMAP=0",
    "-DWASM_RT_MEMCHECK_BOUNDS_CHECK=1",
    "-DWASM_RT_MAX_CALL_STACK_DEPTH=10000",
    f"-I{WABT / 'include'}",
    f"-I{W2C_RT}",
    f"-I{FPGA / 'host'}",
]


def memmap_header() -> Path:
    """gen/memmap.py as C #defines (ZM_<NAME>), shared by vdump and the testbench."""
    out = OUT / "zm_memmap.h"
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = ["/* GENERATED from gen/memmap.py by tools/video_dump.py. */", "#pragma once"]
    for raw in (FPGA / "gen" / "memmap.py").read_text().splitlines():
        name, sep, value = raw.partition(" = ")
        if sep and name.isupper():
            lines.append(f"#define ZM_{name} {value}u")
    text = "\n".join(lines) + "\n"
    if not out.exists() or out.read_text() != text:
        out.write_text(text)
    return out


def _host_objects(tag: str) -> None:
    """The cart's wasm2c objects; `make host` builds them if they are missing."""
    need = [HOST / tag / "cart.o", HOST / tag / "env.c"] + [HOST / "common" / o for o in COMMON]
    if not all(p.exists() for p in need):
        subprocess.run(["make", "-C", str(FPGA), "host", f"CART={tag}"], check=True)


def build(tag: str) -> Path:
    """Link vdump for one cart; the copies keep it stable while build/host/ is rebuilt."""
    _host_objects(tag)
    work = OUT / tag
    work.mkdir(parents=True, exist_ok=True)
    for f in ["cart.o", "cart.h", "env.c"]:
        shutil.copy2(HOST / tag / f, work / f)
    for f in [*COMMON, "machine.h", "rom.h"]:
        shutil.copy2(HOST / "common" / f, work / f)
    inc = [*CFLAGS, f"-I{work}", f"-I{OUT}", f"-I{SRC}"]
    objs = []
    for src, extra in [
        (work / "env.c", ["-Dw2c_env_hblDispatch=vd_orig_hblDispatch"]),
        (FPGA / "host" / "boot.c", []),
        (SRC / "vdump.c", []),
        (SRC / "vdump_rec.c", []),
    ]:
        obj = work / (src.stem + ".vd.o")
        subprocess.run(["clang", *inc, *extra, "-c", str(src), "-o", str(obj)], check=True)
        objs.append(str(obj))
    exe = work / "vdump"
    common = [str(work / o) for o in COMMON]
    subprocess.run(["clang", *objs, str(work / "cart.o"), *common, "-lm", "-lpthread", "-o", str(exe)], check=True)
    return exe


def build_synth() -> Path:
    """vsynth: machine-video alone, driven by the scenarios in vsynth_scen.c."""
    _host_objects("union_intro")  # any cart: only build/host/common is needed
    work = OUT / "_synth"
    work.mkdir(parents=True, exist_ok=True)
    common = ["machine.o", "rt.o", "rt-mem.o", "rt-exc.o"]
    for f in [*common, "machine.h"]:
        shutil.copy2(HOST / "common" / f, work / f)
    inc = [*CFLAGS, f"-I{work}", f"-I{OUT}", f"-I{SRC}"]
    objs = []
    for src in ["vsynth.c", "vsynth_scen.c", "vdump_rec.c"]:
        obj = work / (Path(src).stem + ".o")
        subprocess.run(["clang", *inc, "-c", str(SRC / src), "-o", str(obj)], check=True)
        objs.append(str(obj))
    exe = work / "vsynth"
    subprocess.run(["clang", *objs, *[str(work / o) for o in common], "-lm", "-o", str(exe)], check=True)
    return exe


def synth(scenario: str) -> Path:
    """Record a vsynth scenario; returns the directory holding f1.* .. fN.*."""
    memmap_header()
    exe = build_synth()
    out = OUT / "_synth" / scenario
    out.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(exe), str(out), scenario], check=True, timeout=600)
    return out


def dump(tag: str, frames: list[int], calls: list[str] | None = None) -> Path:
    """Record `frames` of cart `tag`; returns the directory holding f<N>.*."""
    memmap_header()
    exe = build(tag)
    out = OUT / tag / "frames"
    out.mkdir(parents=True, exist_ok=True)
    args = [str(exe), str(out), *map(str, frames)]
    for c in calls or []:
        args += ["--call", c]
    subprocess.run(args, check=True, timeout=600)
    return out


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--synth":
        print(synth(sys.argv[2]))
        sys.exit(0)
    if len(sys.argv) < 3:
        sys.exit("usage: video_dump.py <cart-tag> <frame>... [--call F:name:args]")
    rest = sys.argv[2:]
    call_args = [rest[i + 1] for i, a in enumerate(rest) if a == "--call"]
    nums = [int(a) for i, a in enumerate(rest) if a != "--call" and (i == 0 or rest[i - 1] != "--call")]
    print(dump(sys.argv[1], nums, call_args))
