"""The music block's writer (cycles/bsndinfo.h) against its layout (glass/src/map_cart.zig,
via gen/glass_cart.py): the words the glass's snd_info.zig decodes are the words the firmware
writes. The header is compiled for the host with ZM_SND_INFO pointed at an array, and a few
calls in the firmware's order dump the block after each step."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "gen"))
import glass_cart as mc  # noqa: E402  (gen/ is on the path only from here)

DRIVER = r"""
#include <stdio.h>
#include <stdint.h>
static uint32_t g_block[SND_INFO_WORDS];
#define ZM_SND_INFO ((volatile uint32_t*)g_block)
#include "bsndinfo.h"
static void dump(void) {
    for (unsigned i = 0; i < SND_INFO_WORDS; i++) printf("%u%c", (unsigned)g_block[i], i + 1 < SND_INFO_WORDS ? ' ' : '\n');
}
int main(void) {
    sndinfo_boot(ROUTE_BARD); dump();
    sndinfo_song(ROUTE_BARD, "auf_weidersehen_monty_digi.sndh", 3); dump();
    sndinfo_started(NATIVE_BEAT_DIS); dump();
    sndinfo_render(3000000, 735); sndinfo_render(1000000, 735); sndinfo_render(5000000, 1470); dump();
    sndinfo_render(4000000, 735); dump();
    sndinfo_song(ROUTE_ZIGGY, "x.xm", 0); dump();
    sndinfo_song(ROUTE_BARD, "none", 0); dump();
    sndinfo_song(ROUTE_BARD, "odd.xyz", 0); dump();
    sndinfo_song(ROUTE_BARD, "a_name_longer_than_the_block_holds_0123456789_0123456789_0123456789.mod", 0); dump();
    sndinfo_song(ROUTE_BARD, "b.sndh", 1); sndinfo_started(NATIVE_BEAT_DIS); sndinfo_mode(3); dump();
    sndinfo_mode(1); dump();
    sndinfo_song(ROUTE_BARD, "c.sndh", 1); dump();
    return 0;
}
"""


@pytest.fixture(scope="module")
def steps(tmp_path_factory: pytest.TempPathFactory) -> list[list[int]]:
    cc = shutil.which("cc")
    if not cc:
        pytest.skip("no host C compiler")
    d = tmp_path_factory.mktemp("sndinfo")
    (d / "drv.c").write_text(DRIVER)
    exe = d / "drv"
    subprocess.run([cc, "-std=c11", "-Wall", "-Werror", "-include", str(FPGA / "gen/glass_cart.h"),
                    "-I", str(FPGA / "cycles"), "-I", str(FPGA / "gen"), "-o", str(exe), str(d / "drv.c")], check=True)
    out = subprocess.run([str(exe)], check=True, capture_output=True, text=True).stdout
    return [[int(x) for x in line.split()] for line in out.splitlines()]


def head(w: list[int]) -> tuple[int, int, int, int]:
    h = w[mc.SI_HEAD]
    return h & 0xFF, h >> 8 & 0xFF, h >> 16 & 0xFF, h >> 24


def name(w: list[int]) -> str:
    raw = b"".join(x.to_bytes(4, "little") for x in w[mc.SI_NAME :])
    return raw.split(b"\0")[0].decode()


def test_boot_is_a_whole_block_with_no_song(steps: list[list[int]]) -> None:
    w = steps[0]
    assert w[mc.SI_MAGIC] == mc.SND_INFO_MAGIC
    assert head(w) == (mc.SND_INFO_VERSION, mc.ROUTE_BARD, mc.PLAYER_NONE, 0)
    assert len(w) == mc.SND_INFO_WORDS and w[mc.SI_SEQ] % 2 == 0


def test_a_song_then_its_start(steps: list[list[int]]) -> None:
    req, started = steps[1], steps[2]
    assert head(req)[1:] == (mc.ROUTE_BARD, mc.PLAYER_SNDH, 0)
    assert req[mc.SI_TUNE] == 3 and name(req) == "auf_weidersehen_monty_digi.sndh"
    assert req[mc.SI_FLAGS] & mc.SIF_STARTED == 0
    assert started[mc.SI_FLAGS] & mc.SIF_STARTED and head(started)[3] == mc.NATIVE_BEAT_DIS
    assert all(s[mc.SI_SEQ] % 2 == 0 for s in steps) and steps[2][mc.SI_SEQ] > steps[1][mc.SI_SEQ]


def test_the_peak_is_the_dearest_render_per_sample(steps: list[list[int]]) -> None:
    w = steps[3]
    assert (w[mc.SI_CYCLES], w[mc.SI_SAMPLES]) == (5000000, 1470)  # the last render
    # 3 Mc / 735 = 4082 a sample stays the peak over 1360 and 3401, though 5 Mc is the most cycles
    assert (w[mc.SI_PEAK_CYCLES], w[mc.SI_PEAK_SAMPLES]) == (3000000, 735)
    w = steps[4]  # 5442 a sample: the new peak
    assert (w[mc.SI_PEAK_CYCLES], w[mc.SI_PEAK_SAMPLES]) == (4000000, 735)


def test_players_by_extension_and_a_new_song_clears_the_cost(steps: list[list[int]]) -> None:
    xm, none, odd, long = steps[5], steps[6], steps[7], steps[8]
    assert head(xm)[1:3] == (mc.ROUTE_ZIGGY, mc.PLAYER_XM)
    assert xm[mc.SI_PEAK_SAMPLES] == 0 and xm[mc.SI_FLAGS] == 0
    assert head(none)[2] == mc.PLAYER_NONE
    assert head(odd)[2] == mc.PLAYER_UNKNOWN
    assert head(long)[2] == mc.PLAYER_MOD and len(name(long)) == mc.SND_NAME_MAX


def mode(w: list[int]) -> int:
    return w[mc.SI_FLAGS] >> mc.SIF_MODE_SHIFT & mc.SIF_MODE_MASK


def test_a_mode_switch_is_published_and_a_new_song_clears_it(steps: list[list[int]]) -> None:
    hq, st, fresh = steps[9], steps[10], steps[11]
    assert mode(hq) == 3 and hq[mc.SI_FLAGS] & mc.SIF_STARTED  # the started bit kept
    assert mode(st) == 1 and st[mc.SI_FLAGS] & mc.SIF_STARTED and st[mc.SI_SEQ] > hq[mc.SI_SEQ]
    assert mode(fresh) == 0 and fresh[mc.SI_FLAGS] == 0  # the reader derives it from native again
    assert all(s[mc.SI_SEQ] % 2 == 0 for s in steps)
