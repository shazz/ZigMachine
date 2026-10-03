"""The seal on the core: the sealed VexRiscv (vexgen `:seal`) in Verilator runs
tests/seal/, where every allowed access goes through, every forbidden one traps
with the right mcause and mtval and never reaches the bus, and the gates are
timed (tests/seal/seal.S says what each case is).

Needs Verilator, riscv64-unknown-elf-gcc and the sealed netlist:
    vexgen/gen.sh I4D4Seal:4096:1:4096:1:seal
Skipped without them. Break tests (ZM_RTL_BREAK=1) rebuild the model with one
rule of rtl/seal/zm_seal.v broken and require the program to fail.
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
from test_rtl_seal import seal_map  # after the path insert

CORE = FPGA / "build/vexgen/VexRiscv_I4D4Seal.v"
PROG = FPGA / "tests/seal"
BUILD = FPGA / "build/tests/seal/core"
TOOLS = ("verilator", "riscv64-unknown-elf-gcc")
missing = [t for t in TOOLS if shutil.which(t) is None] + ([] if CORE.exists() else [str(CORE)])
pytestmark = pytest.mark.skipif(bool(missing), reason=f"needs {', '.join(missing)} (see the docstring)")

# (id, text in zm_seal.v, broken text)
MUTANTS = [
    ("u_reads_all", "assign r = user ? u_r : 1'b1;", "assign r = 1'b1;"),
    ("u_writes_all", "assign w = user ? u_w : 1'b1;", "assign w = 1'b1;"),
    ("u_runs_all", "assign x = user ? u_x : ~u_w;", "assign x = user ? 1'b1 : ~u_w;"),
    ("m_runs_cart_data", "assign x = user ? u_x : ~u_w;", "assign x = user ? u_x : 1'b1;"),
]


def _elf(out: Path) -> Path:
    elf = out / "seal.elf"
    srcs = ["seal.S", "seal_gate.S", "seal_data.S"]
    cmd = ["riscv64-unknown-elf-gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-nostdlib", "-nostartfiles"]
    subprocess.run([*cmd, "-T", "link.ld", *srcs, "-o", str(elf)], cwd=PROG, check=True)
    return elf


def _model(seal_v: Path, out: Path) -> Path:
    obj = out / "obj"
    shutil.rmtree(obj, ignore_errors=True)
    cmd = ["verilator", "--cc", "--exe", "--build", "-j", "4", "-O2", "-Wno-fatal", "-Wno-lint", "-Wno-style"]
    cmd += ["--top-module", "VexRiscv", f"-I{FPGA / 'rtl/seal'}", "--Mdir", str(obj), "-o", "seal_core_tb"]
    cmd += [str(CORE), str(seal_v), str(FPGA / "tests/tb/seal_core_tb.cpp")]
    subprocess.run(cmd, check=True, capture_output=True)
    return obj / "seal_core_tb"


def _run(seal_v: Path, out: Path) -> subprocess.CompletedProcess[str]:
    out.mkdir(parents=True, exist_ok=True)
    tb, elf = _model(seal_v, out), _elf(out)
    return subprocess.run([str(tb), str(elf)], capture_output=True, text=True, timeout=300, check=False)


def test_program_sections_are_the_windows() -> None:
    m = seal_map()
    ld = (PROG / "link.ld").read_text()
    for section, key in [(".fw", "FW"), (".code", "CODE"), (".rodata", "RODATA"), (".data", "DATA")]:
        assert re.search(rf"^\s*\{section}\s+0x{m[f'ZS_{key}_BASE']:08x}\s*:", ld, re.MULTILINE | re.IGNORECASE), (
            section
        )
    assert re.search(rf"^\s*\.linear\s+0x{m['ZS_LINEAR_BASE']:08x}\s*:", ld, re.MULTILINE | re.IGNORECASE)
    assert f"{m['ZS_VIDEO_BASE']:#x}" in (PROG / "seal.inc").read_text()


def test_sealed_core() -> None:
    r = _run(FPGA / "rtl/seal/zm_seal.v", BUILD)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "EXIT 0 GUARD 0 UNMAPPED 0" in r.stdout
    ecalls, calls = (int(v) for v in re.findall(r"^REPORT 0x\w+ (\d+)$", r.stdout, re.MULTILINE)[-2:])
    # Generous bounds: a gate is tens of cycles, not hundreds.
    assert 100 * 20 < ecalls < 100 * 120, ecalls
    assert 100 * 20 < calls < 100 * 120, calls
    print(f"seal gates: ecall round trip {ecalls / 100:.1f} cycles, fetch-fault call {calls / 100:.1f} cycles")


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("name", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_seal_leaks(name: str, old: str, new: str) -> None:
    work = BUILD / "mutants" / name
    work.mkdir(parents=True, exist_ok=True)
    text = (FPGA / "rtl/seal/zm_seal.v").read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique"
    (work / "zm_seal.v").write_text(text.replace(old, new))
    r = _run(work / "zm_seal.v", work)
    assert r.returncode != 0, f"{name} went unnoticed:\n{r.stdout}"
