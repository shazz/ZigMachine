"""The range-limited D-cache invalidate after a CHISEL op (cycles/bdinval.h, bblit.c step 4).

Two halves:
- coverage: machine/blitter.zig runs natively on the blitter scripts test_rtl_blitter.py plays
  into the RTL (edges + random), and every 32-byte line of memory whose bytes an op changed must
  be one bdi_range() invalidated (tests/blitter_ref/dinval_check.zig). The RTL writes the same
  bytes as the machine (test_rtl_blitter.py), so this covers every op, clip and stride it can do.
- the core: the board's cart core (VexRiscv_I16w2D4SealFpu) in Verilator runs tests/dcache/,
  where the CPU caches a destination's old pixels, a stand-in for CHISEL rewrites them behind
  the cache, and step 4 runs: without an invalidate the CPU reads stale pixels (the case is
  real), with bdi_range() it reads the new ones and an unrelated line stays cached, with the
  whole-cache invalidate (the old step 4) the unrelated line is refilled. The same sentinel
  caught the wrong-path sweep bdinval.h's bdi_inval_all() guards against (its break test).

Needs zig, Verilator, riscv64-unknown-elf-gcc and build/vexgen/VexRiscv_I16w2D4SealFpu.v
(cycles/board.mk FPU_CORE); each half skips without its tools. ZM_RTL_BREAK=1 breaks
bdinval.h one rule at a time and requires the coverage check to fail.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tests"))
sys.path.insert(0, str(FPGA / "tools"))
import video_dump  # after the path insert: writes build/vdump/zm_memmap.h
from blitter_dinval import dinval_script
from blitter_edges import edge_script
from blitter_random import make_script

BUILD = FPGA / "build" / "tests" / "dcache"
ZIG = os.environ.get("ZIG", str(Path.home() / ".local/zig/0.16.0/zig"))
CORE = FPGA / "build/vexgen/VexRiscv_I16w2D4SealFpu.v"
SCRIPTS = {
    "dinval": dinval_script,
    "edges": edge_script,
    "random1": lambda: make_script(1, 400),
    "random2": lambda: make_script(2, 400),
}
CORE_TOOLS = [t for t in ("verilator", "riscv64-unknown-elf-gcc") if shutil.which(t) is None]
# (id, text in bdinval.h, broken text): each rule of the range, broken one at a time.
MUTANTS = [
    ("span_drops_its_last_line", "a < end; a += BDI_LINE", "a + BDI_LINE < end; a += BDI_LINE"),
    ("span_starts_unaligned", "first & ~(uintptr_t)(BDI_LINE - 1)", "first"),
    ("rows_miss_the_last", "j < rows; j++", "j + 1 < rows; j++"),
    ("rows_ignore_the_stride", "first += ds)", "first += w)"),
    ("triangle_third_vertex_dropped", "ZM_BLIT_CMD_LINE ? 2 : 3", "ZM_BLIT_CMD_LINE ? 2 : 2"),
    ("box_right_edge_exclusive", "bdi_max(b.x1, x + 1)", "bdi_max(b.x1, x)"),
    ("clip_right_edge_ignores_the_origin", "cx + bdi_u16(r, ZM_BLIT_CLIP_W)", "bdi_u16(r, ZM_BLIT_CLIP_W)"),
    ("clip_bottom_edge_ignores_the_origin", "cy + bdi_u16(r, ZM_BLIT_CLIP_H)", "bdi_u16(r, ZM_BLIT_CLIP_H)"),
    (
        "fullscreen_height_ignored",
        "(int32_t)ZM_PHYSICAL_HEIGHT : (int32_t)ZM_HEIGHT",
        "(int32_t)ZM_HEIGHT : (int32_t)ZM_HEIGHT",
    ),
]


def _check_exe(header_dir: Path, out: Path) -> Path:
    """dinval_check over the bdinval.h in header_dir (the real one, or a mutant)."""
    out.mkdir(parents=True, exist_ok=True)
    root, blit = FPGA / "tests/blitter_ref/dinval_check.zig", FPGA.parent / "machine/blitter.zig"
    cmd = [ZIG, "build-exe", "-OReleaseSafe", "-lc", f"-I{header_dir}", f"-I{video_dump.memmap_header().parent}"]
    cmd += [str(FPGA / "tests/blitter_ref/dinval_host.c"), "--dep", "blitter", f"-Mroot={root}", f"-Mblitter={blit}"]
    subprocess.run([*cmd, f"-femit-bin={out / 'dinval_check'}"], check=True, cwd=out, capture_output=True)
    return out / "dinval_check"


def _check(exe: Path) -> dict[str, subprocess.CompletedProcess[str]]:
    return {
        n: subprocess.run([str(exe), f"{n}.txt"], cwd=BUILD, capture_output=True, text=True, timeout=600)
        for n in SCRIPTS
    }


@pytest.fixture(scope="module")
def scripts() -> None:
    BUILD.mkdir(parents=True, exist_ok=True)
    for name, make in SCRIPTS.items():
        (BUILD / f"{name}.txt").write_text("\n".join(make().lines) + "\n")


def test_every_changed_line_is_invalidated(scripts: None) -> None:
    for name, r in _check(_check_exe(FPGA / "cycles", BUILD / "check")).items():
        assert r.returncode == 0, f"{name}:\n{r.stderr}"
        m = re.search(r"DINVAL runs (\d+) range (\d+) full (\d+) empty (\d+) lines (\d+) uncovered 0", r.stderr)
        assert m, r.stderr
        _runs, ranged, full, _empty, _lines = (int(v) for v in m.groups())
        print(f"{name}: {r.stderr.strip()}")
        # the point of the change: most ops get a range, and the whole-cache fallback still happens
        assert ranged > full > 0, r.stderr


def _elf(mode: int, inc: Path = FPGA / "cycles") -> Path:
    elf = inc / f"dcache_m{mode}.elf" if inc != FPGA / "cycles" else BUILD / f"dcache_m{mode}.elf"
    cmd = ["riscv64-unknown-elf-gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-O2", "-nostdlib", "-ffreestanding"]
    cmd += [f"-DMODE={mode}", f"-I{inc}", f"-I{video_dump.memmap_header().parent}", "-T", "link.ld"]
    subprocess.run([*cmd, "start.S", "dcache.c", "-o", str(elf)], cwd=FPGA / "tests/dcache", check=True)
    return elf


@pytest.fixture(scope="module")
def core_tb() -> Path:
    if CORE_TOOLS or not CORE.exists():
        pytest.skip(f"needs {', '.join(CORE_TOOLS) or CORE}")
    obj = BUILD / "obj"
    cmd = ["verilator", "--cc", "--exe", "--build", "-j", "4", "-O2", "-Wno-fatal", "-Wno-lint", "-Wno-style"]
    cmd += ["--top-module", "VexRiscv", f"-I{FPGA / 'rtl/seal'}", "--Mdir", str(obj), "-o", "dcache_tb"]
    cmd += [str(CORE), str(FPGA / "rtl/seal/zm_seal.v"), str(FPGA / "tests/tb/dcache_tb.cpp")]
    subprocess.run(cmd, check=True, capture_output=True)
    return obj / "dcache_tb"


def _core(tb: Path, mode: int, inc: Path = FPGA / "cycles") -> tuple[int, dict[int, int], str]:
    r = subprocess.run([str(tb), str(_elf(mode, inc))], capture_output=True, text=True, timeout=300, check=False)
    rep = {int(v) // 1000000: int(v) % 1000000 for v in re.findall(r"^REPORT (\d+)$", r.stdout, re.MULTILINE)}
    return r.returncode, rep, r.stdout


def test_without_an_invalidate_the_cpu_reads_stale_pixels(core_tb: Path) -> None:
    code, _, out = _core(core_tb, 0)
    assert code == 10, f"the planted stale line was not read stale: the case proves nothing\n{out}"


def test_the_range_drops_the_stale_lines_and_keeps_the_rest(core_tb: Path) -> None:
    code, rep, out = _core(core_tb, 1)
    assert code == 0, out
    assert rep[4] == 0, f"the range invalidated a line outside the op's box\n{out}"
    assert rep[9] == 1 << 8, f"only the full-screen clear (case 8) may take the whole-cache fallback\n{out}"
    _, full, _ = _core(core_tb, 2)
    assert full[4] > 0, "the whole-cache invalidate kept the unrelated line: the sentinel proves nothing"
    print(f"cycles (warm): 37x9 FILL {rep[6]}, 320x4 FILL {rep[7]}, 16x16 tile {rep[8]}, whole cache {rep[3]}")


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
def test_an_unguarded_fallback_flush_sweeps_on_the_wrong_path(core_tb: Path) -> None:
    """Without the nops, the fallback's flush, fetched past `if (!bdi_range())`, sweeps the cache."""
    work = BUILD / "mutants" / "fallback_unguarded"
    work.mkdir(parents=True, exist_ok=True)
    text = (FPGA / "cycles/bdinval.h").read_text()
    old = '"nop\\n nop\\n .word(0x500F)\\n"'
    assert text.count(old) == 1
    (work / "bdinval.h").write_text(text.replace(old, '".word(0x500F)\\n"'))
    code, rep, out = _core(core_tb, 1, work)
    assert code != 0 or rep[4] > 0, f"the unguarded flush went unnoticed\n{out}"


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("name", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_range_misses_a_line(name: str, old: str, new: str, scripts: None) -> None:
    work = BUILD / "mutants" / name
    work.mkdir(parents=True, exist_ok=True)
    text = (FPGA / "cycles/bdinval.h").read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique"
    (work / "bdinval.h").write_text(text.replace(old, new))
    results = _check(_check_exe(work, work))
    assert any(r.returncode != 0 for r in results.values()), f"{name} went unnoticed"
