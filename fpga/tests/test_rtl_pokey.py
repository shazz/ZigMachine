"""The POKEY RTL (rtl/audio/zm_pokey*.v) against its Zig model
(libs/zig/players/pokey.zig), bit for bit.

tests/pokey_ref runs the model natively on a register-write script
(pokey_scripts.py) and dumps the four channel levels after every machine
cycle; tests/tb/pokey_tb.cpp plays the same script into the RTL in Verilator
and requires the same levels, every cycle. Two scripts of all 256 AUDCTL values
and every distortion, on a fast enable (a machine cycle every 24 clocks); and a
prefix of one on the real 100 MHz enables, NTSC (63 / 3520) and PAL
(901 / 50805, the `pal` input), to prove the parameters and the select.

Needs Verilator (skipped without it). Break tests (ZM_RTL_BREAK=1) break one
rule of the RTL at a time and require a failure.
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
from pokey_scripts import make_script, short_script

BUILD = FPGA / "build" / "tests" / "pokey"
ZIG = os.environ.get("ZIG", str(Path.home() / ".local/zig/0.16.0/zig"))
MODEL = FPGA.parent / "libs/zig/players/pokey.zig"
RTL = ["rtl/audio/zm_audio_frac.v", "rtl/audio/zm_pokey_poly.v", "rtl/audio/zm_pokey_pair.v", "rtl/audio/zm_pokey.v"]
FAST = (1, 24)  # CEN_INC, CEN_MOD: room for a burst of writes between two cycles
REAL = (63, 3520)
PAL = (901, 50805)  # zm_pokey PAL_INC / PAL_MOD
SCRIPTS = {"seed1": lambda: make_script(1), "seed2": lambda: make_script(2), "real": lambda: short_script(3, 60_000)}

pytestmark = pytest.mark.skipif(shutil.which("verilator") is None, reason="needs verilator")

# (id, file, text, broken text): each must make the testbench fail on seed1.
MUTANTS = [
    ("single_delay", "zm_pokey_pair.v", "SINGLE = 3'd3", "SINGLE = 3'd2"),
    ("joined_delay", "zm_pokey_pair.v", "JOINED = 3'd6", "JOINED = 3'd5"),
    ("joined_no_wrap", "zm_pokey_pair.v", "else if (joined) c_lo <= 8'hFF;", ""),
    ("poly17_tap", "zm_pokey_poly.v", "~(s17[0] ^ s17[5])", "~(s17[0] ^ s17[3])"),
    ("poly9_tap", "zm_pokey_poly.v", "~(s17[0] ^ s17[4])", "~(s17[0] ^ s17[5])"),
    ("poly4_xor", "zm_pokey_poly.v", "~(s4[0] ^ s4[1])", "(s4[0] ^ s4[1])"),
    ("poly5_gate", "zm_pokey.v", "if (!c[7] && !b5)", "if (!c[7] && b5)"),
    ("dist_bit6", "zm_pokey.v", "else if (c[6]) next_out = b4;", ""),
    ("base15", "zm_pokey.v", "div114 == 7'd113", "div114 == 7'd112"),
    ("hp_source", "zm_pokey.v", "b[2] ? out[0] : hp[0]", "b[0] ? out[0] : hp[0]"),
    ("hp2_off", "zm_pokey.v", "hp[1] <= !audctl[1]", "hp[1] <= 1'b1 ||!audctl[1]"),
    ("ch3_fast_bit", "zm_pokey.v", ".tick_lo(audctl[5] || base)", ".tick_lo(audctl[6] || base)"),
    ("init_runs_bases", "zm_pokey.v", "if (rst || init) begin", "if (rst) begin"),
    ("init_runs_polys", "zm_pokey.v", ".clr(rst || init)", ".clr(rst)"),
    ("vol_only", "zm_pokey.v", "(c[4] || o)", "(o)"),
    ("stimer_keeps_out", "zm_pokey.v", "if (rst || stimer) begin", "if (rst) begin"),
]


def _run(cmd: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=BUILD, capture_output=True, text=True, timeout=900, check=False,
                          env={**os.environ, **(env or {})})


def build_tb(cen: tuple[int, int], root: Path = FPGA, out: Path = BUILD / "fast") -> Path:
    """The Verilator testbench over the RTL under `root` with enable INC/MOD `cen`, built in `out`."""
    cmd = ["verilator", "--cc", "--exe", "--build", "-j", "4", "-O2", "-Wall", "-Wno-fatal"]
    cmd += ["--top-module", "zm_pokey", f"-GCEN_INC={cen[0]}", f"-GCEN_MOD={cen[1]}", "--Mdir", str(out)]
    cmd += ["-o", "pokey_tb", *(str(root / s) for s in RTL), str(FPGA / "tests/tb/pokey_tb.cpp")]
    r = subprocess.run(cmd, capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stdout + r.stderr
    return out / "pokey_tb"


@pytest.fixture(scope="module")
def oracle() -> dict[str, Path]:
    """The Zig model's trace of each script."""
    BUILD.mkdir(parents=True, exist_ok=True)
    root = FPGA / "tests/pokey_ref/pokey_ref.zig"
    cmd = [ZIG, "build-exe", "-OReleaseSafe", "--dep", "pokey", f"-Mroot={root}", f"-Mpokey={MODEL}"]
    subprocess.run([*cmd, f"-femit-bin={BUILD / 'pokey_ref'}"], check=True, cwd=BUILD)
    for name, make in SCRIPTS.items():
        (BUILD / f"{name}.txt").write_text("\n".join(make().lines) + "\n")
        r = _run([str(BUILD / "pokey_ref"), f"{name}.txt", f"{name}.trace"])
        assert r.returncode == 0, r.stderr
    return {name: BUILD / f"{name}.trace" for name in SCRIPTS}


def test_the_model_passes_its_own_tests() -> None:
    test = FPGA.parent / "libs/zig/players/pokey_test.zig"
    r = subprocess.run([ZIG, "test", str(test)], capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stderr


def test_the_scripts_cover_every_audctl_value_and_distortion(oracle: dict[str, Path]) -> None:
    for name in ("seed1", "seed2"):
        s = make_script(int(name[-1]))
        writes = [line.split()[1:] for line in s.lines if line.startswith("w")]
        assert {int(v, 16) for a, v in writes if int(a, 16) == 0x8} == set(range(256))
        for ch in range(4):
            audc = {int(v, 16) for a, v in writes if int(a, 16) == 2 * ch + 1}
            assert {v >> 5 for v in audc} == set(range(8)), f"{name}: channel {ch + 1}"
            assert any(v & 0x10 for v in audc) and any(not v & 0x10 for v in audc)
        assert s.cycles >= 600_000
        trace = oracle[name].read_bytes()
        assert len(trace) == 2 * s.cycles


@pytest.mark.parametrize("name", ["seed1", "seed2"])
def test_the_rtl_matches_the_model_every_cycle(name: str, oracle: dict[str, Path]) -> None:
    r = _run([str(build_tb(FAST)), f"{name}.txt", str(oracle[name])])
    print(r.stdout)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "bit-exact" in r.stdout


def test_the_rtl_matches_on_the_real_100mhz_enable(oracle: dict[str, Path]) -> None:
    r = _run([str(build_tb(REAL, out=BUILD / "real")), "real.txt", str(oracle["real"])])
    print(r.stdout)
    assert r.returncode == 0, r.stdout + r.stderr


def test_the_rtl_matches_on_the_pal_enable_and_runs_at_its_rate(oracle: dict[str, Path]) -> None:
    tb = build_tb(REAL, out=BUILD / "real")
    pal = _run([str(tb), "real.txt", str(oracle["real"])], env={"ZM_POKEY_PAL": "1"})
    ntsc = _run([str(tb), "real.txt", str(oracle["real"])])
    assert pal.returncode == 0, pal.stdout + pal.stderr
    # The same machine cycles take more system clocks at PAL's slower enable.
    clocks = [int(re.search(r"(\d+) clocks", r.stdout).group(1)) for r in (pal, ntsc)]
    assert clocks[0] > clocks[1] * (1789772.7 / 1773447.5) * 0.999


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("name", "file", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_pokey_rule_is_caught(name: str, file: str, old: str, new: str, oracle: dict[str, Path]) -> None:
    work = BUILD / "mutants" / name
    shutil.rmtree(work, ignore_errors=True)
    for src in RTL:
        (work / src).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(FPGA / src, work / src)
    path = work / "rtl/audio" / file
    text = path.read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique in {file}"
    path.write_text(text.replace(old, new))
    r = _run([str(build_tb(FAST, work, work / "obj")), "seed1.txt", str(oracle["seed1"])])
    assert r.returncode != 0, f"{name} went unnoticed:\n{r.stdout}"
