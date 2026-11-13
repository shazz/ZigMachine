"""ZIGGY's big reads on the board's read path (review/ZIGGY_BIG_READS_STUDY.md): the board's cart
core (VexRiscv_I16w2D16w2SealFpuZmxE: I$ 16 KB 2-way, D$ 16 KB 2-way) in Verilator over the
real WishboneHP (posted=8, no read bypass: the board's combo16 build), the HP register slices and
the sim DDR with HP_LATENCY (20 cycles AR to first beat: the latency that makes a bare line miss
the board's ~48 cycles, BENCH_REPORTS.md ld.miss). tests/zigread/reads.c runs the bench cart's
loops; every bridge variant must read the same checksums, and the variants' cycles are the study's
table. ZM_RTL_BREAK=1: a prefetch that ignores the store rule must change a checksum.

Needs Verilator, riscv64-unknown-elf-gcc and build/vexgen/VexRiscv_I16w2D16w2SealFpuZmxE.v
(`make vexgen-zmx`); skips without them."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
BUILD = FPGA / "build/tests/zigread"
CORE = Path(os.environ.get("ZM_ZIGREAD_CORE", FPGA / "build/vexgen/VexRiscv_I16w2D16w2SealFpuZmxE.v"))
# ZM_ZIGREAD_INIT: a reads.c image built elsewhere (a box with Verilator but no RISC-V gcc)
PREBUILT = os.environ.get("ZM_ZIGREAD_INIT")
NEEDS = ("verilator",) if PREBUILT else ("verilator", "riscv64-unknown-elf-gcc", "riscv64-unknown-elf-objcopy")
TOOLS = [t for t in NEEDS if not shutil.which(t)]
LATENCY = 20  # soc/hp_sim.py HP_LATENCY
KERNELS = {1: "write 256 KB", 2: "read 4 KB x16", 3: "read 192 KB", 4: "line misses x2048", 5: "copy 64 KB",
           6: "random lines x2048", 7: "store-then-stream"}  # fmt: skip
BYTES = {1: 262144, 2: 65536, 3: 196608, 5: 65536}
Result = dict[int, tuple[int, int]]  # kernel -> (cycles, checksum)


def build_tb(tag: str, opts: list[str], latency: int = LATENCY, break_: str = "") -> Path:
    """The Verilated harness for one WishboneHP variant (`opts`: its keywords set True)."""
    if TOOLS or not CORE.exists():
        pytest.skip(f"needs {', '.join(TOOLS) or CORE}")
    obj = BUILD / f"obj_{tag}_{latency}"
    exe = obj / "zigread_tb"
    obj.mkdir(parents=True, exist_ok=True)
    top = obj / "zigread.v"
    gen = [sys.executable, str(FPGA / "tests/zigread_top.py"), str(top), "--latency", str(latency)]
    gen += [a for o in opts for a in ("--opt", o)] + (["--break", break_] if break_ else [])
    subprocess.run(gen, check=True, cwd=obj, env={**os.environ, "PYTHONPATH": str(FPGA)})
    cmd = ["verilator", "--cc", "--exe", "--build", "-j", "4", "-O2", "-Wno-fatal", "-Wno-lint", "-Wno-style"]
    cmd += ["--top-module", "zigread", f"-I{FPGA / 'rtl/seal'}", "--Mdir", str(obj), "-o", "zigread_tb"]
    cmd += [str(top), str(CORE), str(FPGA / "rtl/seal/zm_seal.v"), str(FPGA / "tests/tb/zigread_tb.cpp")]
    subprocess.run(cmd, check=True, capture_output=True)
    return exe


def build_fw() -> Path:
    """reads.c, and its DDR image as zm_ddr.init (64-bit words from the window's start)."""
    if PREBUILT:
        return Path(PREBUILT)
    BUILD.mkdir(parents=True, exist_ok=True)
    elf, bin_, init = BUILD / "reads.elf", BUILD / "reads.bin", BUILD / "zm_ddr.init"
    src = FPGA / "tests/zigread"
    cmd = ["riscv64-unknown-elf-gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-O2", "-nostdlib", "-ffreestanding"]
    cmd += ["-T", str(FPGA / "tests/dcache/link.ld"), str(FPGA / "tests/dcache/start.S"), "reads.c", "-lgcc"]
    subprocess.run([*cmd, "-o", str(elf)], cwd=src, check=True, capture_output=True)
    subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary", str(elf), str(bin_)], check=True)
    data = bin_.read_bytes()
    data += bytes(-len(data) % 8)
    words = (int.from_bytes(data[i : i + 8], "little") for i in range(0, len(data), 8))
    init.write_text("".join(f"{w:016x}\n" for w in words))
    return init


def run(exe: Path, init: Path) -> Result:
    run_dir = exe.parent
    shutil.copy(init, run_dir / "zm_ddr.init")
    r = subprocess.run([str(exe)], cwd=run_dir, capture_output=True, text=True, timeout=3600, check=False)
    assert r.returncode == 0, r.stdout[-2000:]
    rep = [int(v) for v in re.findall(r"^REPORT (\d+)$", r.stdout, re.MULTILINE)]
    return {rep[i]: (rep[i + 1], rep[i + 2]) for i in range(0, len(rep), 3)}


def table(res: dict[str, Result]) -> str:
    """One line a kernel: cycles (and MB/s at 100 MHz, 1 MB = 2^20 B) for each variant."""
    lines = []
    for k, name in KERNELS.items():
        cells = []
        for tag, r in res.items():
            c = r[k][0]
            mbs = f" {BYTES[k] * 100e6 / c / 1048576:.1f} MB/s" if k in BYTES and c else ""
            cells.append(f"{tag}: {c}{mbs}")
        lines.append(f"{name:20} " + " | ".join(cells))
    return "\n".join(lines)


VARIANTS = {"base": [], "fast": ["fast_burst"], "pf": ["fast_burst", "prefetch"]}  # zm_board_mem.READ_MODES
BREAK = pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")


@pytest.fixture(scope="module")
def results() -> dict[str, Result]:
    init = build_fw()
    only = os.environ.get("ZM_ZIGREAD_VARIANTS")
    names = only.split(",") if only else list(VARIANTS)
    return {n: run(build_tb(n, VARIANTS[n]), init) for n in names}


def test_print_the_table(results: dict[str, Result]) -> None:
    print("\n" + table(results))


def test_every_variant_reads_the_same_data(results: dict[str, Result]) -> None:
    for k, name in KERNELS.items():
        assert len({r[k][1] for r in results.values()}) == 1, (name, {t: r[k][1] for t, r in results.items()})


def test_burst_acks_take_clocks_off_every_miss(results: dict[str, Result]) -> None:
    base, fast = results["base"], results["fast"]
    for k in (3, 4, 5, 6):  # every kernel that misses, random ones included
        assert fast[k][0] <= 0.92 * base[k][0], (KERNELS[k], base[k][0], fast[k][0])


def test_the_prefetch_speeds_up_streams_and_leaves_random_reads_alone(results: dict[str, Result]) -> None:
    fast, pf = results["fast"], results["pf"]
    assert pf[3][0] <= 0.7 * fast[3][0], ("read 192 KB", fast[3][0], pf[3][0])
    assert pf[5][0] <= 0.7 * fast[5][0], ("copy 64 KB", fast[5][0], pf[5][0])
    assert pf[6][0] <= 1.01 * fast[6][0], ("random lines", fast[6][0], pf[6][0])


@BREAK
def test_break_a_prefetch_that_ignores_a_store_reads_the_old_word(results: dict[str, Result]) -> None:
    broken = run(build_tb("pf_nostore", VARIANTS["pf"], break_="nostore"), build_fw())
    assert broken[7][1] != results["base"][7][1], "the store-then-stream kernel must catch it"
