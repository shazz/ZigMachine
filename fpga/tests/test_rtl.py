"""RTL tests: each module is compiled to C++ by Yosys's CXXRTL backend (yowasp,
so no system simulator is needed) and driven by a C++ testbench in tests/tb/.

A testbench prints its failures and exits non-zero; this file only builds and
runs it. Add a module by adding a row to RTL_TESTS.
"""

import subprocess
from pathlib import Path

import pytest
import yowasp_yosys

FPGA = Path(__file__).resolve().parent.parent
BUILD = FPGA / "build" / "tests"
CXXRTL_INCLUDE = Path(yowasp_yosys.__file__).parent / "share/include/backends/cxxrtl/runtime"

# (top module, its sources, the testbench)
RTL_TESTS = [
    ("zm_vtiming", ["rtl/video/zm_vtiming.v"], "tests/tb/zm_vtiming_tb.cpp"),
]


def _cxxrtl(top: str, sources: list[str]) -> Path:
    out = BUILD / f"{top}.cc"
    reads = " ".join(str(FPGA / s) for s in sources)
    script = f"read_verilog -I{FPGA / 'gen'} {reads}; hierarchy -top {top}; proc; write_cxxrtl {out}"
    rc = yowasp_yosys.run_yosys(["-q", "-p", script])
    assert rc == 0, f"yosys failed on {top}"
    return out


def _compile_and_run(top: str, cc: Path, tb: str) -> subprocess.CompletedProcess[str]:
    exe = BUILD / f"{top}_tb"
    subprocess.run(
        ["clang++", "-std=c++17", "-O2", f"-I{CXXRTL_INCLUDE}", f"-I{cc.parent}", str(FPGA / tb), "-o", str(exe)],
        check=True,
    )
    return subprocess.run([str(exe)], capture_output=True, text=True, timeout=300, check=False)


@pytest.mark.parametrize(("top", "sources", "tb"), RTL_TESTS, ids=[t[0] for t in RTL_TESTS])
def test_rtl(top: str, sources: list[str], tb: str) -> None:
    assert (FPGA / "gen" / "memmap.vh").exists(), "run `make memmap` first"
    BUILD.mkdir(parents=True, exist_ok=True)
    result = _compile_and_run(top, _cxxrtl(top, sources), tb)
    assert result.returncode == 0, result.stdout + result.stderr
