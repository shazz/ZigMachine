"""The primitive self-test (rtl/board/prim_test/prim_test_core.v, `make prim-test`) in
CXXRTL, driven over GP0 by tests/tb/prim_test_tb.cpp: every lane must PASS in
simulation (the primitives it maps to are what is under test on silicon, not the
RTL), a restart must clear and re-run, LOOP must accumulate.

Break tests (ZM_RTL_BREAK=1): the core built with BREAK_TEST=<lane> inverts bit 0
of that lane's reference; the testbench must see exactly that lane FAIL, with its
first error at the first compare and bad bits 0x1, and every other lane PASS.
One lane of each kind: a block RAM, byte enables, a ROM, a LUTRAM, an SRL, a
DSP, the carry chain, the wide muxes.
"""

import os
import subprocess
import sys
from pathlib import Path

import pytest
import yowasp_yosys

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import prim_test_read  # after the path insert

BUILD = FPGA / "build" / "tests" / "prim_test"
SOURCES = sorted((FPGA / "rtl/board/prim_test").glob("*.v")) + [FPGA / "tests/tb/prim_cells_sim.v"]
TB = FPGA / "tests/tb/prim_test_tb.cpp"
CXXRTL_INCLUDE = Path(yowasp_yosys.__file__).parent / "share/include/backends/cxxrtl/runtime"
# One lane of each kind (prim_test_lanes.v; names from tools/prim_test_read.py)
BREAKS = [0, 7, 14, 22, 24, 25, 27, 32, 40, 41, 43]


def build(break_lane: int = -1) -> Path:
    """The testbench against the core, with BREAK_TEST = break_lane; returns the executable."""
    out = BUILD / f"break{break_lane}" if break_lane >= 0 else BUILD / "ok"
    out.mkdir(parents=True, exist_ok=True)
    cc = out / "prim_test_core.cc"
    reads = " ".join(str(s) for s in SOURCES)
    chparam = f"chparam -set BREAK_TEST {break_lane} prim_test_core; " if break_lane >= 0 else ""
    script = f"read_verilog {reads}; {chparam}hierarchy -top prim_test_core; proc; flatten; write_cxxrtl {cc}"
    assert yowasp_yosys.run_yosys(["-q", "-p", script]) == 0, "yosys failed on prim_test_core"
    exe = out / "prim_test_tb"
    cmd = ["clang++", "-std=c++17", "-O1", f"-I{CXXRTL_INCLUDE}", f"-I{out}", str(TB), "-o", str(exe)]
    subprocess.run(cmd, check=True)
    return exe


def run(exe: Path, broken: int = -1) -> tuple[int, str]:
    result = subprocess.run([str(exe), str(broken)], capture_output=True, text=True, timeout=1800, check=False)
    return result.returncode, result.stdout + result.stderr


def test_every_lane_passes_in_simulation_and_restart_and_loop_work() -> None:
    code, out = run(build())
    assert code == 0, out
    assert "PASS: 45 lanes, 0 failures" in out, out


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize("lane", BREAKS, ids=[prim_test_read.LANES[i][0] for i in BREAKS])
def test_a_lane_with_a_wrong_reference_bit_reports_fail(lane: int) -> None:
    exe = build(lane)
    code, out = run(exe, lane)
    assert code == 0, f"the testbench did not see lane {lane} fail alone:\n{out}"
    code, out = run(exe, -1)
    assert code != 0 and f"lane {lane} failed" in out, f"lane {lane}'s break went unnoticed:\n{out}"
