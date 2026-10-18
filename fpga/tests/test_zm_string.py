"""cycles/zm_string.c: the word-storing memset/memcpy/memmove the rv32 firmware links ahead of
picolibc's byte loops. Byte-exact against the host libc (tests/tb/zm_string_test.c), and the
rv32 build must really store words (the whole point: one blocking DDR write per word, not per byte)
and must not call itself (GCC's loop-to-memset rewrite would make it recurse)."""

import shutil
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
WORK = FPGA / "build/tests"
SRC = FPGA / "cycles/zm_string.c"
RV_CC = "riscv64-unknown-elf-gcc"


def test_matches_the_host_libc_byte_for_byte() -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    exe = WORK / "zm_string_test"
    cmd = ["clang", "-std=c11", "-O2", "-Wall", "-Werror", "-fno-builtin", str(FPGA / "tests/tb/zm_string_test.c")]
    subprocess.run([*cmd, "-o", str(exe)], check=True)
    r = subprocess.run([exe], capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stdout + r.stderr


def _rv32_asm() -> str:
    if shutil.which(RV_CC) is None:
        pytest.skip(f"no {RV_CC}")
    r = subprocess.run(
        [RV_CC, "-march=rv32im", "-mabi=ilp32", "-O2", "-std=gnu11", "-S", "-o", "-", str(SRC)],
        capture_output=True, text=True, check=True)
    return r.stdout


def test_rv32_build_stores_words_and_never_recurses() -> None:
    asm = _rv32_asm()
    assert asm.count("\tsw\t") >= 8, "memset/memcpy must store words"
    calls = [ln.strip() for ln in asm.splitlines() if ln.strip().startswith(("call", "tail", "jal\t"))]
    recursive = [c for c in calls if c.split("\t")[-1] in ("memset", "memcpy", "memmove")]
    assert recursive == [], f"the string functions must not call themselves (GCC loop rewrite): {calls}"
