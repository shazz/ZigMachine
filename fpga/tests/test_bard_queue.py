"""The BARD queue's board path across the S2C bank (cycles/bardq_s2c.h, host/bardq.h): BARD publishes
the commands it took, its position and its events; ZIGGY copies them into the cart's block (libs/zig/
bard.zig's layout) after the cart's frame, as docs/sealed-loader.js bardPublish does on the page.
apps/bard_queue_check.mjs holds the page to the native host sample for sample; this holds the board's
transport to the same block, with the bank and the cart's memory as arrays.

ZM_RTL_BREAK=1 runs the break test: the slot check (an event a later one overwrote) removed from a copy of the
header must fail the lapped-events check."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent

DRIVER = r"""
#include <stdio.h>
#include "cycles/bardq_s2c.h"
static uint32_t s2c[32], blk[16 + 4 * 8 + 4 * 4];
static void dump(const char* tag) {
    printf("%s", tag);
    for (unsigned i = 0; i < 12; i++) printf(" %u", (unsigned)blk[i]);
    for (unsigned i = 0; i < 16; i++) printf(" %u", (unsigned)blk[16 + 32 + i]);
    printf("\n");
}
static void ev(uint32_t* n, uint32_t t, uint32_t kind, uint32_t arg) {
    uint32_t e[3] = {t, kind, arg};
    bq_s2c_event(s2c, (*n)++, e);
}
int main(void) {
    uint32_t seen = 0, n = 0;
    for (unsigned i = 0; i < 32; i++) s2c[i] = 0xA5A5A5A5u; /* an earlier run's words */
    bq_s2c_boot(s2c);
    blk[BQ_MAGIC_W] = BQ_MAGIC; blk[BQ_CAP_W] = 8; blk[BQ_EV_CAP_W] = 4; blk[BQ_HEAD_W] = 5;
    bq_state s = {.pos = 1234, .anchored = 0};
    bq_s2c_state(s2c, 3, &s, n);
    bq_s2c_collect(s2c, blk, &seen); dump("unanchored");
    s.anchored = 1;
    ev(&n, 100, 1, 0x123456); ev(&n, 200, 2, 8580);
    bq_s2c_state(s2c, 3, &s, n);
    bq_s2c_collect(s2c, blk, &seen); dump("two");
    bq_s2c_state(s2c, 9, &s, n); /* past what the cart wrote */
    bq_s2c_collect(s2c, blk, &seen); dump("past");
    blk[BQ_EV_TAIL_W] = 2; /* the cart read both */
    for (uint32_t i = 0; i < 5; i++) ev(&n, 300 + i, 1, i);
    bq_s2c_state(s2c, 5, &s, n);
    bq_s2c_collect(s2c, blk, &seen); dump("lapped");
    for (uint32_t i = 0; i < 3; i++) ev(&n, 400 + i, 1, i);
    bq_s2c_state(s2c, 5, &s, n);
    bq_s2c_collect(s2c, blk, &seen); dump("full");
    return 0;
}
"""
W = {"tail": 5, "pos": 7, "anchored": 8, "ev_head": 9, "ev_lost": 11}


def run(work: Path, header: Path) -> dict[str, list[int]]:
    (work / "cycles").mkdir(parents=True, exist_ok=True)
    (work / "host").mkdir(exist_ok=True)
    shutil.copy(header, work / "cycles/bardq_s2c.h")
    shutil.copy(FPGA / "cycles/snd_mailbox.h", work / "cycles/snd_mailbox.h")
    shutil.copy(FPGA / "host/bardq.h", work / "host/bardq.h")
    (work / "d.c").write_text(DRIVER)
    subprocess.run(["cc", "-std=c11", "-Wall", "-Werror", f"-I{work}", "-o", str(work / "d"), str(work / "d.c")], check=True)
    out = subprocess.run([str(work / "d")], check=True, capture_output=True, text=True).stdout
    return {ln.split()[0]: [int(v) for v in ln.split()[1:]] for ln in out.splitlines()}


def event(r: list[int], i: int) -> list[int]:
    return r[12 + 4 * i : 12 + 4 * i + 4]


def check(r: dict[str, list[int]]) -> None:
    assert r["unanchored"][W["tail"]] == 3 and r["unanchored"][W["pos"]] == 0  # no position before the anchor
    two = r["two"]
    assert two[W["pos"]] == 1234 and two[W["anchored"]] == 1 and two[W["ev_head"]] == 2
    assert event(two, 0) == [100, 1, 0x123456, 0] and event(two, 1) == [200, 2, 8580, 1]
    assert r["past"][W["tail"]] == 3  # a tail past the cart's head is never copied
    lapped = r["lapped"]  # five events, three slots: the two oldest lost, the newest three copied
    assert lapped[W["ev_lost"]] == 2 and lapped[W["ev_head"]] == 5
    assert [event(lapped, i % 4)[0] for i in (2, 3, 4)] == [302, 303, 304]
    full = r["full"]  # the cart reads nothing more: one fits its ring of four, two are lost
    assert full[W["ev_head"]] == 6 and full[W["ev_lost"]] == 4


def test_the_board_answer_lands_in_the_cart_block_as_the_page_writes_it(tmp_path: Path) -> None:
    check(run(tmp_path, FPGA / "cycles/bardq_s2c.h"))


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="break tests: ZM_RTL_BREAK=1")
def test_break_events_past_the_slots_copied_anyway_is_caught(tmp_path: Path) -> None:
    src = (FPGA / "cycles/bardq_s2c.h").read_text()
    rule = "        if ((s2c[S_BQ_EVN] >> 1) - i > S_BQ_SLOTS) {"
    assert rule in src
    broken = tmp_path / "broken.h"
    broken.write_text(src.replace(rule, "        if (0) {"))
    with pytest.raises(AssertionError):
        check(run(tmp_path / "w", broken))
