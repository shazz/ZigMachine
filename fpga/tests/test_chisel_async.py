"""CHISEL's lazy wait (cycles/bchisel.c, BLIT_ASYNC): the driver on the host over a model of the
engine and its tap (tests/chisel_async/host.c), where a register store that reaches the tap while
the engine is BUSY is dropped, as rtl/blitter/zm_blit_regs.v drops it.

- A synchronous hwBlit returns with CHISEL idle and its box's D$ lines dropped (as before).
- An async one returns while CHISEL runs, invalidates nothing yet; the next op waits for it, drops
  the FIRST op's lines (taken at its GO, though the cart has since rewritten the registers), and
  runs with the registers the cart stored meanwhile (the replay puts back what the tap dropped).
- A NOP hwBlit (zg.chisel_async.sync) and the env hook (HOST_CHISEL_SYNC) both wait.

ZM_RTL_BREAK=1 breaks each rule in a copy of bchisel.c and requires the model to notice.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import video_dump  # after the path insert: writes build/vdump/zm_memmap.h

HERE = FPGA / "tests/chisel_async"
BUILD = FPGA / "build/tests/chisel_async"
SOURCES = ("bchisel.c", "bchisel.h", "bdinval.h")
CASES = ("sync_waits", "sync_invalidates_its_box", "lazy_returns_at_once", "lazy_invalidates_the_first_ops_box",
         "replay_restores_dropped_registers", "nop_syncs", "env_hook_syncs")  # fmt: skip
# (id, text in bchisel.c, broken text, the case that must then fail)
MUTANTS = [
    ("no_replay", "replay(g_r);", "", "replay_restores_dropped_registers"),
    ("box_at_sync", "finish(g_r, &g_plan);", "bdi_plan_op(g_r, g_r[ZM_BLIT_COMMAND], &g_plan); finish(g_r, &g_plan);",
     "lazy_invalidates_the_first_ops_box"),
    ("no_wait_at_next_op", "    bchisel_sync();\n    uint8_t cmd", "    uint8_t cmd", "nop_syncs"),
    ("always_lazy", "if (r[ZM_BLIT_ASYNC]) {", "if (1) {", "sync_waits"),
]  # fmt: skip
needs_cc = pytest.mark.skipif(shutil.which("cc") is None, reason="needs a host C compiler")


def _build(work: Path, edit: tuple[str, str] | None = None) -> Path:
    work.mkdir(parents=True, exist_ok=True)
    for name in SOURCES:
        shutil.copy(FPGA / "cycles" / name, work / name)
    for stub in (HERE / "stubs").iterdir():
        shutil.copy(stub, work / stub.name)
    if edit:
        text = (work / "bchisel.c").read_text()
        assert text.count(edit[0]) == 1, f"the text to break is not unique: {edit[0]!r}"
        (work / "bchisel.c").write_text(text.replace(edit[0], edit[1]))
    exe = work / "chisel_async"
    inc = [f"-I{work}", f"-I{video_dump.memmap_header().parent}"]
    cmd = ["cc", "-std=c11", "-O1", "-Wall", "-Werror", "-Wno-unused-function", *inc, str(HERE / "host.c"), "-o", str(exe)]
    subprocess.run(cmd, check=True, capture_output=True, text=True)
    return exe


def _run(exe: Path) -> dict[str, bool]:
    out = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60).stdout
    return {ln.split()[1].rstrip(":"): ln.startswith("OK") for ln in out.splitlines() if ln[:2] in ("OK", "FA")}


@needs_cc
def test_the_lazy_wait_keeps_every_rule() -> None:
    got = _run(_build(BUILD / "real"))
    assert set(got) == set(CASES), got
    assert all(got.values()), [c for c, ok in got.items() if not ok]


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@needs_cc
@pytest.mark.parametrize(("name", "old", "new", "case"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_lazy_wait_is_caught(name: str, old: str, new: str, case: str) -> None:
    got = _run(_build(BUILD / "mutants" / name, (old, new)))
    assert got.get(case) is False, f"{name} went unnoticed: {got}"
