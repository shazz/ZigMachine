"""ASTROLABE's mailbox protocol (SPIKE, docs/ARM_FPU_COPROC.md) across its three copies.

- cycles/bastro_box.h (ZIGGY's firmware) must say what glass/src/astro_box.zig (the ARM),
  machine/sdk/astro.zig (the descriptor) and soc/zm_astro.py (the window) say: every number.
- cycles/bastro_post.h, ZIGGY's side, natively against a scripted glass (tests/tb/astro_post_test.c):
  served, results back, the words copied per op class, refusals, no worker, not taken (withdrawn,
  then dead until the BEAT moves), taken but never done (TIMEOUT, no rerun), a late worker.

ZM_RTL_BREAK=1 runs the break tests: each rule broken in a copy of the header must fail the test.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
HDR = FPGA / "cycles/bastro_box.h"
POST = FPGA / "cycles/bastro_post.h"
BUILD = FPGA / "build/tests/astro"


def _zig_consts(path: Path) -> dict[str, int]:
    pat = re.compile(r"^pub const (\w+): u32 = (0x[0-9A-Fa-f_]+|\d+);", re.M)
    return {k: int(v.replace("_", ""), 0) for k, v in pat.findall(path.read_text())}


def _c_consts() -> dict[str, int]:
    pat = re.compile(r"^#define ASTRO_(\w+) (0x[0-9A-Fa-f]+|\d+)u", re.M)
    return {k: int(v, 0) for k, v in pat.findall(HDR.read_text())}


def test_the_firmware_header_says_what_glass_the_machine_and_the_soc_say() -> None:
    c = _c_consts()
    box = _zig_consts(FPGA / "glass/src/astro_box.zig")
    abi = _zig_consts(ROOT / "machine/sdk/astro.zig")
    for k in ("MAGIC", "VERSION", "BEAT", "SEQ", "TAKEN", "DONE", "COUNT", "MEM_OFF", "MEM_SIZE", "ARM_NS", "RET", "DESC0", "ID", "PROTO"):
        assert c[k] == box[k], k
    for k in ("DESC_WORDS", "W_OP", "W_N", "W_C", "W_STATUS", "W_CYCLES", "W_S0", "W_R", "OP_MASK", "OP_VADD", "MAX_COUNT", "ST_BAD_DESC", "ST_TIMEOUT"):
        assert c[k] == abi[k], k
    soc = (FPGA / "soc/zm_astro.py").read_text()
    assert f"ASTRO_WINDOW = {c['WINDOW']:#x}" in soc


def _run(header_dir: Path) -> subprocess.CompletedProcess[str]:
    exe = header_dir / "astro_post_test"
    subprocess.run(["cc", "-std=c11", "-O1", "-Wall", "-Werror", f"-I{header_dir}", str(FPGA / "tests/tb/astro_post_test.c"), "-o", str(exe)], check=True)
    return subprocess.run([str(exe)], capture_output=True, text=True, timeout=60, check=False)


def _tree(work: Path) -> Path:
    shutil.rmtree(work, ignore_errors=True)
    (work / "cycles").mkdir(parents=True)
    shutil.copy(HDR, work / "cycles")
    shutil.copy(POST, work / "cycles")
    return work


def test_ziggys_side_of_the_protocol() -> None:
    result = _run(_tree(BUILD / "ok"))
    assert result.returncode == 0, result.stdout + result.stderr


MUTANTS = [
    ("no_withdraw", "b[ASTRO_SEQ] = 0; /* withdrawn", "(void)0; /* withdrawn"),
    ("never_dead", "c->dead = 1, c->dead_beat", "c->dead = 0, c->dead_beat"),
    ("beat_ignored", "if (c->dead && b[ASTRO_BEAT] == c->dead_beat) return 0;", "if (c->dead) return 0;"),
    ("rerun_on_timeout", "return c->timeouts++, ASTRO_ST_TIMEOUT;", "return c->timeouts++, BASTRO_UNSERVED;"),
    ("seq_zero", "++c->seq ? c->seq : ++c->seq", "c->seq++"),
    ("scalar_words", "hi = array ? ASTRO_W_C : ASTRO_W_S0 + 5", "hi = array ? ASTRO_W_C : ASTRO_W_S0 + 3"),
    ("array_s0", "c->box[slot + ASTRO_W_S0] = bastro_rd(c, at + 4 * ASTRO_W_S0);", "(void)0;"),
    ("result_hi", "bastro_wr(c, at + 4 * ASTRO_W_R + 4, b[slot + ASTRO_W_R + 1]);", "(void)0;"),
    ("no_magic", "if (b[ASTRO_MAGIC] != ASTRO_ID || b[ASTRO_VERSION] != ASTRO_PROTO) return 0;", ""),
    ("list_bound", "desc % 8 == 0 &&", "desc % 4 == 0 &&"),
]


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("name", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_protocol_rule_is_caught(name: str, old: str, new: str) -> None:
    work = _tree(BUILD / "mutants" / name)
    text = (work / "cycles/bastro_post.h").read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique"
    (work / "cycles/bastro_post.h").write_text(text.replace(old, new))
    result = _run(work)
    assert result.returncode != 0, f"{name} went unnoticed:\n{result.stdout}"
