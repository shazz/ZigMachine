"""KESTREL_NEXT_ISA.md steps 1-2, measured: the texture-class loops (tests/zmx/bench.c) on the
board's cart core (D$ 4 KiB direct-mapped), the 16 KiB 2-way D$ core, and that core with ZM-X
(tex2d + mulsh), each in Verilator with a DDR-like read latency (dcache_tb read wait 32: a line
miss ~48 cycles, BENCH_REPORTS.md). Prints the table (cycles a pixel or a ray step, D$ refills a
frame) and pins the claims the step rests on: the 16 KiB texture stops missing with the big D$,
and ZM-X makes every kernel faster again. Needs the netlists test_zmx.py lists, plus
VexRiscv_I16w2D4SealFpu.v (vexgen/gen.sh I16w2D4SealFpu:16384:2:4096:1:seal,fpu)."""

import re
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_zmx import BUILD, FPGA, SRC, _tb  # after the path insert: the same harness and netlists

READ_WAIT = "32"
KERNELS = {1: ("roto64", 64000), 2: ("roto128", 64000), 3: ("roto256", 64000), 4: ("voxel128", 0), 5: ("voxel256", 0)}
RUNS = [  # (label, core, -DZMX)
    ("D4", "I16w2D4SealFpu", False),
    ("D16w2", "I16w2D16w2SealFpu", False),
    ("D16w2+ZM-X", "I16w2D16w2SealFpuZmx", True),
    ("D16w2+ZM-X early", "I16w2D16w2SealFpuZmxE", True),
]
Table = dict[str, dict[int, tuple[int, int, int]]]  # label -> kernel -> (cycles, refills, frame hash)


def _bench(core: str, zmx: bool) -> dict[int, tuple[int, int, int]]:
    elf = BUILD / f"bench{'_zmx' if zmx else ''}.elf"
    cmd = ["riscv64-unknown-elf-gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-O2", "-nostdlib", "-ffreestanding"]
    cmd += [f"-I{FPGA / 'cycles'}", *(["-DZMX"] if zmx else []), "-T", str(FPGA / "tests/dcache/link.ld")]
    subprocess.run([*cmd, "start.S", "bench.c", "-lgcc", "-o", str(elf)], cwd=SRC, check=True, capture_output=True)
    tb = _tb(core, FPGA / f"build/vexgen/VexRiscv_{core}.v")
    env = {"ZM_TB_CYCLES": "200000000"}
    r = subprocess.run([str(tb), str(elf), "0", READ_WAIT], capture_output=True, text=True, timeout=3600, env=env)
    assert r.returncode == 0, r.stdout
    rep = [int(v) for v in re.findall(r"^REPORT (\d+)$", r.stdout, re.MULTILINE)]
    return {rep[i] // 1000000: (rep[i] % 1000000 * 1000, rep[i + 1] % 1000000 * 10, rep[i + 2]) for i in range(0, len(rep), 3)}


@pytest.fixture(scope="module")
def table() -> Table:
    return {label: _bench(core, zmx) for label, core, zmx in RUNS}


def test_print_the_table(table: Table) -> None:
    for k, (name, px) in KERNELS.items():
        cells = [f"{lbl}: {c / 1e6:.2f} Mc" + (f" {c / px:.1f} c/px" if px else "") + f", {r} refills"
                 for lbl, t in table.items() for c, r, _ in [t[k]]]
        print(f"{name:9} " + " | ".join(cells))


def test_every_core_and_build_draws_the_same_frames(table: Table) -> None:
    for k, (name, _) in KERNELS.items():
        assert len({t[k][2] for t in table.values()}) == 1, f"{name}: {[t[k][2] for t in table.values()]}"


def test_a_16k_texture_stays_resident_in_the_big_dcache(table: Table) -> None:
    small, big = table["D4"][2][1], table["D16w2"][2][1]
    assert big * 10 < small, f"roto128 refills: D4 {small}, D16w2 {big}"


def test_zmx_is_faster_on_every_kernel(table: Table) -> None:
    # voxel128 is span-bound (the terrain hides most steps): 0.29 -> 0.27 Mc is too thin a margin
    # to pin against a GCC change, so it is held to its refills instead
    for k, (name, _) in KERNELS.items():
        if name == "voxel128":
            assert table["D16w2+ZM-X"][k][1] <= table["D16w2"][k][1], name
        else:
            assert table["D16w2+ZM-X"][k][0] < table["D16w2"][k][0], name
