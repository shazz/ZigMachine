"""The ZIGGY bench cart (fpga/cycles/native/bench, decisions.md 2026-10-18): it builds into a lean
image the board's system runs, its log sits where the ARM looks for it, its kernels are the
instruction sequences their figures claim to time, and its test table fits the screen and the
results array. Nothing here runs the cart: the board is the profiler."""

from __future__ import annotations

import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(FPGA / "gen"))
import glass_cart
import glass_map
import native_cart

BENCH = FPGA / "cycles/native/bench"
SPLIT = FPGA / "build/hcycles/split"
needs_rv = pytest.mark.skipif(shutil.which("riscv64-unknown-elf-gcc") is None, reason="the rv32 toolchain builds it")
MAX_RESULTS, NAME_COLS = 128, 16  # bench.h BENCH_MAX_RESULTS; screen.c's name column
EXTRA_RESULTS = 1 + 7 + 9  # calib.empty, the contention series, the frame tests


def build(fpu: bool) -> Path:
    args = ["make", "-s", "native-cart", "NAME=bench", *(["ZM_FPU=1"] if fpu else [])]
    subprocess.run(args, cwd=FPGA, check=True, capture_output=True)
    return SPLIT / ("native_fpu" if fpu else "native") / "bench"


def symbols(elf: Path) -> dict[str, int]:
    out = subprocess.run(["riscv64-unknown-elf-nm", str(elf)], capture_output=True, text=True, check=True).stdout
    return {f[2]: int(f[0], 16) for f in (ln.split() for ln in out.splitlines()) if len(f) == 3}


def log_is_first(elf: Path) -> bool:
    """bench_collect.py finds the log at the header's bss_start: it must be the first .bss object."""
    s = symbols(elf)
    return s["zmb_log"] == s["__cart_bss_start"]


def body(elf: Path, fn: str) -> list[str]:
    """fn's instructions (mnemonic and operands), from objdump."""
    out = subprocess.run(["riscv64-unknown-elf-objdump", "-d", "--no-show-raw-insn", str(elf)],
                         capture_output=True, text=True, check=True).stdout  # fmt: skip
    block = out.split(f"<{fn}>:\n", 1)[1].split("\n\n", 1)[0]
    return [ln.split("\t", 1)[1].strip() for ln in block.splitlines() if "\t" in ln]


@needs_rv
def test_the_bench_builds_to_a_lean_image_this_system_runs() -> None:
    image = (build(fpu=True) / "cart.bin").read_bytes()
    assert native_cart.check(image) == "bench"
    cart_high, bss_end = struct.unpack_from("<I", image, 24)[0], struct.unpack_from("<I", image, 16)[0]
    assert cart_high == 0x100000 + 0x1000 + 0x100000  # the text scratch and 1 MiB of buffers
    assert bss_end > glass_map.CART_CPU_BASE + glass_cart.CART_IMG_AT + len(image)  # .bss past the image


@needs_rv
def test_the_log_is_the_first_bss_object_so_the_arm_finds_it_from_the_header() -> None:
    out = build(fpu=True)
    image = (out / "cart.bin").read_bytes()
    assert log_is_first(out / "cart.elf")
    assert struct.unpack_from("<I", image, 12)[0] == symbols(out / "cart.elf")["zmb_log"]


@needs_rv
def test_a_link_that_does_not_put_log_c_first_is_caught(tmp_path: Path) -> None:
    build(fpu=True)  # the generated headers
    srcs = sorted((str(p) for p in BENCH.glob("*.[cS]")), reverse=True)  # tests_cpu.c (bench_sink) first
    cc = ["riscv64-unknown-elf-gcc", "-march=rv32imf", "-mabi=ilp32f", "-Os", "-ffreestanding", "-nostdlib",
          "-nostartfiles", "-fno-tree-loop-distribute-patterns", f"-I{FPGA / 'cycles'}", f"-I{FPGA / 'cycles/native'}",
          f"-I{BENCH}", f"-I{FPGA / 'gen'}", f"-I{FPGA / 'build/vdump'}", "-Wl,--no-warn-rwx-segments",
          "-Wl,--defsym=ZM_CART_BASE=0x40300000", f"-T{FPGA / 'cycles/cart.ld'}"]  # fmt: skip
    subprocess.run([*cc, "-o", str(tmp_path / "bad.elf"), *srcs, "-lgcc"], check=True, capture_output=True)
    assert not log_is_first(tmp_path / "bad.elf")


@needs_rv
def test_the_probe_has_nothing_but_the_call_between_its_two_counter_loads() -> None:
    insns = body(build(fpu=True) / "cart.elf", "k_time")
    loads = [i for i, s in enumerate(insns) if s.startswith("lw") and "0(t0)" in s]
    assert len(loads) == 2
    window = insns[loads[0] + 1 : loads[1]]
    assert [s.split()[0] for s in window] == ["jalr", "lui"]  # the call, then t0 = the counter again


@needs_rv
@pytest.mark.parametrize(("fn", "op", "count", "length"), [("k_st_sw", "sw", 8, 11), ("k_st_sh", "sh", 8, 11),
                                                           ("k_st_sb", "sb", 8, 11), ("k_ld_seq", "lw", 8, 11),
                                                           ("k_st_alu4", "addi", 8 * 4 + 2, 8 + 8 * 4 + 3),
                                                           ("k_st_alu16", "addi", 8 * 16 + 2, 8 + 8 * 16 + 3)])  # fmt: skip
def test_each_kernel_loop_is_the_accesses_it_claims_and_nothing_else(fn: str, op: str, count: int, length: int) -> None:
    insns = [s.split()[0] for s in body(build(fpu=True) / "cart.elf", fn)]
    assert insns[0] == "srli"  # n / 8 passes
    loop = insns[1 : insns.index("bnez") + 1]
    assert loop.count(op) == count and len(loop) == length


@needs_rv
def test_the_i_cache_kernels_fit_and_overflow_the_16k_two_way_cache() -> None:
    elf = build(fpu=True) / "cart.elf"
    assert 8192 < 4 * len(body(elf, "k_icache_fit")) < 16384
    assert 4 * len(body(elf, "k_icache_over")) > 16384 + 8192  # three lines a set: LRU refetches all


@needs_rv
def test_f32_is_the_fpus_in_the_fpu_build_and_soft_float_without_it() -> None:
    hw = body(build(fpu=True) / "cart.elf", "k_fdiv")
    assert any(s.startswith("fdiv.s") for s in hw)
    soft = subprocess.run(["riscv64-unknown-elf-objdump", "-d", str(build(fpu=False) / "cart.elf")],
                          capture_output=True, text=True, check=True).stdout  # fmt: skip
    assert not re.search(r"\tf(add|mul|div)\.s\t", soft) and "<__divsf3>" in soft


def case_names() -> list[str]:
    names = []
    for src in BENCH.glob("tests_*.c"):
        text = src.read_text()
        names += re.findall(r'\{"([A-Za-z0-9.]+)", \w+, ', text)
        names += [b + s for b in re.findall(r'SIZES\("([a-z.]+)"', text) for s in (".64", ".1K", ".8K", ".32K", ".64K")]
    return names


def test_every_test_has_a_unique_name_that_fits_the_screen_and_the_results() -> None:
    names = case_names()
    assert len(names) == len(set(names)) and len(names) > 80
    assert all(len(n) <= NAME_COLS and " " not in n for n in names)
    assert len(names) + EXTRA_RESULTS <= MAX_RESULTS
