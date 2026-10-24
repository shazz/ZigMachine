"""A disk's executable boot sector on the board (host/bootsec.h): the firmware runs the
sector's own 1 KB of wasm through the wint interpreter (host/wint.h), as the browser runs it
in its engine. Everything here holds the interpreter against node's WebAssembly, the
browser's engine, line for line:

- sysinfo's "No virus" sector and replicants_emlyn's crew note: the whole memory after boot()
  and after every frame, pollCartRequest's chainload at the frame the browser sees it (120, 240);
- every opcode wint runs, on edge and random operands (tests/bootsec_util.py's WAT module),
  traps included (division, out-of-bounds, unreachable);
- what the sandbox refuses or cuts short: float arithmetic, a truncated sector, a loop that
  never ends (fuel), a disk whose sector is not executable.

ZM_RTL_BREAK=1 runs the break tests: each mutant breaks one rule in a copy of the sources and
the differential tests must catch it."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest
from bootsec_util import FPGA, ROOT, WABT, native, node, op_calls, ops_wat, wat2wasm

WORK = FPGA / "build" / "board_bootsec"
SRC = ["bootsec.c", "wint_load.c", "wint_link.c", "wint_scan.c", "wint_num.c", "wint_flow.c", "wint_exec.c"]
SYSINFO = ROOT / "docs/demo-sysinfo.zmd"
REPLICANTS = ROOT / "docs/demo-replicants_emlyn.zmd"
NEEDS = pytest.mark.skipif(not shutil.which("node") or not (WABT / "bin/wat2wasm").exists(), reason="no node or wabt")
BREAK = pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")


def build(host: Path, out: Path) -> Path:
    out.parent.mkdir(parents=True, exist_ok=True)
    srcs = [str(host / s) for s in SRC]
    subprocess.run(["clang", "-std=c11", "-D_POSIX_C_SOURCE=200809L", "-Wall", "-Wextra", "-Werror", "-O2",
                    "-DWINT_MAX_BYTES=65536u", "-DWINT_MAX_TYPES=64", "-DWINT_MAX_FUNCS=256", "-DWINT_MAX_EXPORTS=256",
                    f"-I{host}", str(FPGA / "tests/tb/bootsec_test.c"), *srcs, "-o", str(out)], check=True)  # fmt: skip
    return out


@pytest.fixture(scope="module")
def exe() -> Path:
    return build(FPGA / "host", WORK / "bootsec_test")


@pytest.fixture(scope="module")
def ops() -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    return wat2wasm(ops_wat(), WORK / "ops.wasm")


def sector_lines(exe: Path, disk: Path, frames: int) -> list[str]:
    return native(exe, "sector", disk, str(frames))


@NEEDS
@pytest.mark.parametrize(("disk", "chain"), [(SYSINFO, 120), (REPLICANTS, 240)])
def test_the_sector_writes_the_memory_the_browser_does_and_chainloads_on_its_frame(exe: Path, disk: Path,
                                                                                  chain: int) -> None:
    ours = sector_lines(exe, disk, chain + 10)
    assert ours == node("sector", disk, str(chain + 10))
    assert ours[0].startswith("boot ok ")
    assert ours[-1].split()[:4] == ["f", str(chain), "1", "1"] and len(ours) == chain + 1


@NEEDS
def test_every_opcode_wint_runs_answers_as_the_browsers_engine(exe: Path, ops: Path) -> None:
    calls = op_calls()
    ours = native(exe, "calls", ops, stdin=calls)
    theirs = node("calls", ops, stdin=calls)
    assert len(ours) == len(theirs) == calls.count("\n")
    bad = [(c, a, b) for c, a, b in zip(calls.splitlines(), ours, theirs, strict=True) if a != b]
    assert not bad, f"{len(bad)} calls differ, first: {bad[:5]}"
    assert {"div 0", "oob 0", "unreachable 0"} <= set(ours)  # the traps were reached, not only the values


def _module(tmp: Path, body: str, name: str) -> Path:
    head = '(module (import "env" "memory" (memory 112 112)) (func (export "run") (param i64) (result i64) '
    return wat2wasm(head + body + "))", tmp / f"{name}.wasm")


@NEEDS
@pytest.mark.parametrize(("body", "want"), [
    ("(loop $l (br $l)) (local.get 0)", "fuel 0"),                                    # never ends: fuel, no hang
    ("(i64.reinterpret_f64 (f64.add (f64.const 1) (f64.const 2)))", "load unsupported"),  # float arithmetic
    ("(i64.load (i32.const 0x700000))", "oob 0"),                                     # one byte past the memory
])  # fmt: skip
def test_the_sandbox_cuts_short_what_it_does_not_run(exe: Path, tmp_path: Path, body: str, want: str) -> None:
    m = _module(tmp_path, body, "m")
    assert native(exe, "calls", m, stdin="run 0\n") == [want]


def test_a_truncated_or_corrupt_sector_is_refused_and_the_cart_boots(exe: Path, tmp_path: Path) -> None:
    img = bytearray(SYSINFO.read_bytes())
    img[0x200:0x400] = bytes(0x200)  # the code section cut
    (tmp_path / "cut.zmd").write_bytes(img)
    line = sector_lines(exe, tmp_path / "cut.zmd", 5)
    assert len(line) == 1 and line[0].split()[1] in ("format", "link")


@pytest.mark.parametrize(("disk", "want"), [(SYSINFO, "1"), (REPLICANTS, "1"), (ROOT / "docs/demo-st_replay.zmd", "0"),
                                            (ROOT / "docs/demo-stniccc.zmd", "0")])  # fmt: skip
def test_only_a_v2_sector_that_sums_to_1234_is_executable(exe: Path, disk: Path, want: str) -> None:
    assert native(exe, "exec", disk) == [want]


def test_a_sector_whose_sum_is_off_is_not_executable(exe: Path, tmp_path: Path) -> None:
    img = bytearray(SYSINFO.read_bytes())
    img[0x3FF] ^= 1
    (tmp_path / "off.zmd").write_bytes(img)
    assert native(exe, "exec", tmp_path / "off.zmd") == ["0"]


MUTANTS = [
    ("i32_lt_s_unsigned", "wint_num.c", "case 2: return sa < sb;", "case 2: return a < b;"),
    ("shift_mask", "wint_num.c", "uint32_t s = b & 31;", "uint32_t s = b & 15;"),
    ("load_no_sign", "wint_exec.c", "if ((k & 0x10) && bits < 64)", "if (0 && bits < 64)"),
    ("oob_off_by_one", "wint_exec.c", "if (at + n > w->mem_len) return WINT_T_OOB;", "if (at + n > w->mem_len + 1) return WINT_T_OOB;"),
    ("loop_drops_label", "wint_flow.c", "x->nl -= l + (L->loop ? 0 : 1);", "x->nl -= l + 1;"),
    ("no_data_segments", "wint_link.c", "memcpy(mem + w->data[i].at, m + w->data[i].from,", "memset(mem + w->data[i].at, 0,"),
    ("poll_ignored", "bootsec.c", "return (uint32_t)r == BOOTSEC_CHAINLOAD && b->f_poll >= 0;", "return 0;"),
]  # fmt: skip


@BREAK
@NEEDS
@pytest.mark.parametrize(("name", "file", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_break_each_mutant_is_caught(ops: Path, name: str, file: str, old: str, new: str) -> None:
    host = WORK / "mut" / name
    shutil.rmtree(host, ignore_errors=True)
    shutil.copytree(FPGA / "host", host, ignore=shutil.ignore_patterns("*.o"))
    text = (host / file).read_text()
    assert text.count(old) == 1, f"the text to break is not unique in {file}"
    (host / file).write_text(text.replace(old, new))
    mut = build(host, host / "bootsec_test")
    calls = op_calls()
    caught = native(mut, "calls", ops, stdin=calls) != node("calls", ops, stdin=calls)
    caught = caught or sector_lines(mut, SYSINFO, 130) != node("sector", SYSINFO, "130")
    assert caught, f"mutant {name} survived"
