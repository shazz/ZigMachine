"""ZM-X v1 on the cart core (vexgen `zmx`: ZmXPlugin + ZmMulPlugin), against its twins.

tests/zmx/zmx.c runs on the core in Verilator (tests/tb/dcache_tb.cpp): every op over all
pairs of 16 edge words and 2048 random pairs, checked on the core against cycles/zmx_twin.h
(the C twin trap.c and the native side use), dependent ops back to back (the bypass), and
the encodings next to the ops that are none (each must trap). The core's per-op hashes must
equal tests/zmx/zmx_equiv.zig's over libs/zig/zmx.zig, the spec: RTL = C twin = Zig spec.
Both result placements are run (`zmx`: written from MEMORY, the board's; `zmxearly`: from
EXECUTE). ZM_RTL_BREAK=1: a core without ZM-X, a C twin and a Zig spec each broken one
rule at a time must all be caught.

Needs Verilator, riscv64-unknown-elf-gcc, zig and the netlists
(vexgen/gen.sh I16w2D16w2SealFpuZmx:16384:2:16384:2:seal,fpu,zmx, ...ZmxE ...:zmxearly,
I16w2D16w2SealFpu ...:seal,fpu); each part skips without its tools.
"""

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
BUILD = FPGA / "build" / "tests" / "zmx"
SRC = FPGA / "tests" / "zmx"
ZIG = os.environ.get("ZIG", str(Path.home() / ".local/zig/0.16.0/zig"))
ZMX_ZIG = Path(os.environ.get("ZM_ZMX_ZIG", FPGA.parent / "libs/zig/zmx.zig"))
CORES = {n: FPGA / f"build/vexgen/VexRiscv_{n}.v" for n in ("I16w2D16w2SealFpuZmx", "I16w2D16w2SealFpuZmxE")}
PLAIN = FPGA / "build/vexgen/VexRiscv_I16w2D16w2SealFpu.v"
TOOLS = [t for t in ("verilator", "riscv64-unknown-elf-gcc") if shutil.which(t) is None]
N_OPS = 10
# (id, text in zmx_twin.h, broken text): the C twin, one rule broken at a time.
C_MUTANTS = [
    ("avg8_rounds_up", "l = s >> 1;", "l = (s + 1) >> 1;"),
    ("add8s_clamps_at_254", "s > 255u ? 255u : s", "s > 254u ? 254u : s"),
    ("mulsh_unsigned", "((int64_t)(int32_t)a * (int32_t)b)", "(int64_t)((uint64_t)a * b)"),
    ("tex2d_masks_w_with_h", "((u >> 16) & ((1u << logw) - 1u))", "((u >> 16) & ((1u << logh) - 1u))"),
    ("funnel_off_by_a_byte", "(hi << (32u - 8u * k))", "(hi << (24u - 8u * k + 8u * (k == 1u)))"),
]
# (id, text in zmx.zig, broken text): the Zig spec, broken.
ZIG_MUTANTS = [
    ("avg8_rounds_up", "return (a & b) +% (((a ^ b) >> 1) & L7);", "return (a | b) -% (((a ^ b) >> 1) & L7);"),
    ("mulsh_shift_17", "return @truncate((@as(i64, a) * b) >> shift);", "return @truncate((@as(i64, a) * b) >> (shift + 1));"),
]


def _tb(name: str, netlist: Path) -> Path:
    if TOOLS or not netlist.exists():
        pytest.skip(f"needs {', '.join(TOOLS) or netlist}")
    obj = BUILD / f"obj_{name}"
    exe = obj / "dcache_tb"
    if exe.exists() and exe.stat().st_mtime > netlist.stat().st_mtime:
        return exe
    obj.mkdir(parents=True, exist_ok=True)
    cmd = ["verilator", "--cc", "--exe", "--build", "-j", "4", "-O2", "-Wno-fatal", "-Wno-lint", "-Wno-style"]
    cmd += ["--top-module", "VexRiscv", f"-I{FPGA / 'rtl/seal'}", "--Mdir", str(obj), "-o", "dcache_tb"]
    cmd += [str(netlist), str(FPGA / "rtl/seal/zm_seal.v"), str(FPGA / "tests/tb/dcache_tb.cpp")]
    subprocess.run(cmd, check=True, capture_output=True)
    return exe


def _elf(inc: Path, tag: str) -> Path:
    BUILD.mkdir(parents=True, exist_ok=True)
    elf = BUILD / f"zmx_{tag}.elf"
    cmd = ["riscv64-unknown-elf-gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-O2", "-nostdlib", "-ffreestanding"]
    cmd += [f"-I{inc}", "-T", str(FPGA / "tests/dcache/link.ld"), "start.S", "zmx.c", "-lgcc", "-o", str(elf)]
    subprocess.run(cmd, cwd=SRC, check=True, capture_output=True)
    return elf


def _run(tb: Path, elf: Path) -> tuple[int, list[int], str]:
    env = {**os.environ, "ZM_TB_CYCLES": "50000000"}  # a core without ZM-X traps every op: slow
    r = subprocess.run([str(tb), str(elf)], capture_output=True, text=True, timeout=600, check=False, env=env)
    return r.returncode, [int(v) for v in re.findall(r"^REPORT (\d+)$", r.stdout, re.MULTILINE)], r.stdout


def _spec_hashes(zmx_zig: Path, tag: str) -> list[int]:
    if not zmx_zig.exists() or shutil.which(ZIG) is None and not Path(ZIG).exists():
        pytest.skip(f"needs zig and {zmx_zig}")
    out = BUILD / f"equiv_{tag}"
    out.mkdir(parents=True, exist_ok=True)
    cmd = [ZIG, "build-exe", "-OReleaseSafe", "--dep", "zmx", f"-Mroot={SRC / 'zmx_equiv.zig'}", f"-Mzmx={zmx_zig}"]
    subprocess.run([*cmd, f"-femit-bin={out / 'zmx_equiv'}"], cwd=out, check=True, capture_output=True)
    r = subprocess.run([str(out / "zmx_equiv")], capture_output=True, text=True, check=True)
    return [int(v) for v in re.findall(r"^HASH (\d+)$", r.stderr, re.MULTILINE)]


@pytest.mark.parametrize("name", list(CORES))
def test_every_op_on_the_core_matches_the_c_twin(name: str) -> None:
    code, rep, out = _run(_tb(name, CORES[name]), _elf(FPGA / "cycles", "real"))
    assert code == 0, f"exit {code}: mismatches {rep[N_OPS]}, first (op, a, b, core, twin) {rep[N_OPS + 2:]}\n{out}"
    assert rep[N_OPS] == 0 and rep[N_OPS + 1] == 7, out


@pytest.mark.parametrize("name", list(CORES))
def test_the_core_matches_the_zig_spec(name: str) -> None:
    _, rep, out = _run(_tb(name, CORES[name]), _elf(FPGA / "cycles", "real"))
    assert rep[:N_OPS] == _spec_hashes(ZMX_ZIG, "real"), out


_BREAK = pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")


@_BREAK
def test_a_core_without_zmx_traps_every_op() -> None:
    code, rep, out = _run(_tb("I16w2D16w2SealFpu", PLAIN), _elf(FPGA / "cycles", "real"))
    assert code == 1 and rep[N_OPS] > 0, f"a core without ZM-X passed: the test proves nothing\n{out}"


@_BREAK
@pytest.mark.parametrize(("mut", "old", "new"), C_MUTANTS, ids=[m[0] for m in C_MUTANTS])
def test_a_broken_c_twin_is_caught(mut: str, old: str, new: str) -> None:
    work = BUILD / "mutants" / mut
    work.mkdir(parents=True, exist_ok=True)
    text = (FPGA / "cycles/zmx_twin.h").read_text()
    assert text.count(old) == 1, f"{mut}: the text to break is not unique"
    (work / "zmx_twin.h").write_text(text.replace(old, new))
    code, _, out = _run(_tb("I16w2D16w2SealFpuZmx", CORES["I16w2D16w2SealFpuZmx"]), _elf(work, mut))
    assert code == 1, f"{mut} went unnoticed\n{out}"


@_BREAK
@pytest.mark.parametrize(("mut", "old", "new"), ZIG_MUTANTS, ids=[m[0] for m in ZIG_MUTANTS])
def test_a_broken_zig_spec_is_caught(mut: str, old: str, new: str) -> None:
    if not ZMX_ZIG.exists():
        pytest.skip(f"needs {ZMX_ZIG}")
    work = BUILD / "mutants" / f"zig_{mut}"
    work.mkdir(parents=True, exist_ok=True)
    text = ZMX_ZIG.read_text()
    assert text.count(old) == 1, f"{mut}: the text to break is not unique"
    (work / "zmx.zig").write_text(text.replace(old, new))
    _, rep, _ = _run(_tb("I16w2D16w2SealFpuZmx", CORES["I16w2D16w2SealFpuZmx"]), _elf(FPGA / "cycles", "real"))
    assert rep[:N_OPS] != _spec_hashes(work / "zmx.zig", f"zig_{mut}"), f"{mut} went unnoticed"


# zmx_hw.h's import macros, each with the funct3/funct7 the core decodes (zmx.c's table).
CART_CALLS = {
    "w2c_env_zmMulsh16(e, a, b)": (0, 1), "w2c_env_zmMulsh15(e, a, b)": (1, 1),
    "w2c_env_zmFunnel1(e, a, b)": (1, 2), "w2c_env_zmFunnel2(e, a, b)": (2, 2), "w2c_env_zmFunnel3(e, a, b)": (3, 2),
    "w2c_env_zmAdd8s(e, a, b)": (0, 3), "w2c_env_zmSub8s(e, a, b)": (0, 4), "w2c_env_zmAvg8(e, a, b)": (0, 5),
    "w2c_env_zmAdd8(e, a, b)": (0, 6), "w2c_env_zmTex2d(e, a, b, 9u)": (7, 9),
}


def test_a_zmx_cart_build_turns_each_import_into_one_op() -> None:
    """zm_variant.h with ZM_ZMX: a wasm2c call is the op itself, tex2d's constant dims folded."""
    if TOOLS:
        pytest.skip(f"needs {', '.join(TOOLS)}")
    BUILD.mkdir(parents=True, exist_ok=True)
    src = '#include <stdint.h>\n#include "zm_variant.h"\nstruct w2c_env;\n'
    for i, call in enumerate(CART_CALLS):
        src += f"uint32_t f{i}(struct w2c_env* e, uint32_t a, uint32_t b) {{ (void)e; return {call}; }}\n"
    (BUILD / "calls.c").write_text(src)
    cmd = ["riscv64-unknown-elf-gcc", "-march=rv32im", "-mabi=ilp32", "-O2", "-DZM_ZMX", f"-I{FPGA / 'cycles'}", "-c"]
    subprocess.run([*cmd, str(BUILD / "calls.c"), "-o", str(BUILD / "calls.o")], check=True, capture_output=True)
    dis = subprocess.run(["riscv64-unknown-elf-objdump", "-d", str(BUILD / "calls.o")], capture_output=True, text=True)
    for i, (f3, f7) in enumerate(CART_CALLS.values()):
        body = dis.stdout.split(f"<f{i}>:")[1].split("\n\n")[0]
        words = [int(w, 16) for w in re.findall(r"^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s", body, re.MULTILINE)]
        ops = [w for w in words if w & 0x7F == 0x0B]
        assert len(ops) == 1 and (ops[0] >> 12) & 7 == f3 and ops[0] >> 25 == f7, f"f{i}:\n{body}"
        assert len(words) == 2, f"f{i}: more than the op and ret\n{body}"
