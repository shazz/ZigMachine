"""BARD jobs (zg.bard.job, table 1.24): the C side's view of the cart's job block (host/bjob.h, read by
cycles/bsound_job.c on ZIGGY and by nothing else in C: BARD runs libs/zig/bard_jobs/server.zig itself)
must be libs/zig/bard_jobs/layout.zig's, word for word, or ZIGGY's poll reads `done` in the wrong place
and waits out its 0.5 s timeout on every job.

ZM_RTL_BREAK=1 runs the break test: a header whose `done` word moved must fail the check."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
LAYOUT = FPGA.parent / "libs/zig/bard_jobs/layout.zig"

DRIVER = r"""
#include <stdio.h>
#include "bjob.h"
int main(void) {
    printf("MAGIC %u\nSLOTS %u\nHEAD_WORDS %u\nJOB_WORDS %u\nBLOCK_BYTES %u\n", (unsigned)BJ_MAGIC,
           (unsigned)BJ_SLOTS, (unsigned)BJ_HEAD_WORDS, (unsigned)BJ_JOB_WORDS, (unsigned)BJ_BLOCK_BYTES);
    printf("magic %d\nslots %d\nhead %d\n", BJ_MAGIC_W, BJ_SLOTS_W, BJ_HEAD_W);
    printf("op %d\nseq %d\ndone %d\nerr %d\ncycles %d\nresult %d\na %d\n", BJ_OP_W, BJ_SEQ_W, BJ_DONE_W, BJ_ERR_W,
           BJ_CYCLES_W, BJ_RESULT_W, BJ_ARG_W);
    uint32_t b[1024] = {0};
    printf("slot9 %d\n", (int)(bj_slot(b, 9) - b)); /* job 9 is slot 1 */
    return 0;
}
"""


def c_view(work: Path, header: Path) -> dict[str, int]:
    work.mkdir(parents=True, exist_ok=True)
    (work / "bjob.h").write_text(header.read_text())
    (work / "d.c").write_text(DRIVER)
    subprocess.run(["cc", "-std=c11", "-Wall", "-Werror", f"-I{work}", "-o", str(work / "d"), str(work / "d.c")], check=True)
    out = subprocess.run([str(work / "d")], check=True, capture_output=True, text=True).stdout
    return {k: int(v) for k, v in (ln.split() for ln in out.splitlines())}


def zig_view() -> dict[str, int]:
    src = LAYOUT.read_text()
    consts = {m[1]: int(m[2].replace("_", ""), 0) for m in re.finditer(r"pub const (\w+): u32 = (0x[0-9a-fA-F_]+|\d+);", src)}
    head = re.search(r"pub const H = struct \{(.*?)\};", src, re.S)
    job = re.search(r"pub const Job = extern struct \{(.*?)\};", src, re.S)
    assert head and job
    v = {k: consts[k] for k in ("MAGIC", "SLOTS", "HEAD_WORDS", "JOB_WORDS")}
    v["BLOCK_BYTES"] = 4 * (v["HEAD_WORDS"] + v["SLOTS"] * v["JOB_WORDS"])
    v.update({m[1]: int(m[2]) for m in re.finditer(r"pub const (\w+) = (\d+);", head[1])})
    fields = re.findall(r"^\s*(\w+): [^,]+,", job[1], re.M)
    v.update({f: i for i, f in enumerate(fields)})  # every field before the args is one u32 word
    v["slot9"] = v["HEAD_WORDS"] + v["JOB_WORDS"] * (9 % v["SLOTS"])
    return v


def test_the_c_header_is_the_zig_layout_word_for_word(tmp_path: Path) -> None:
    assert c_view(tmp_path, FPGA / "host/bjob.h") == zig_view()


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="break tests: ZM_RTL_BREAK=1")
def test_break_a_moved_done_word_is_caught(tmp_path: Path) -> None:
    src = (FPGA / "host/bjob.h").read_text()
    rule = "BJ_DONE_W = 2, BJ_ERR_W = 3"
    assert rule in src
    broken = tmp_path / "broken.h"
    broken.write_text(src.replace(rule, "BJ_DONE_W = 3, BJ_ERR_W = 2"))
    with pytest.raises(AssertionError):
        assert c_view(tmp_path / "w", broken) == zig_view()
