"""The audio-state mirror (cycles/aud_state.h, cycles/bmirror.c): BARD publishes the players' mode,
SNDH position and YM registers in its S2C bank, the cart CPU reads them and writes into the cart's
ZigOS fields what site/js/sealed-loader.js writes in the browser, and only what changed. Before it,
the board never wrote them: D-BUG's scroller and logo sat still and music_debug drew no scope.

The headers and bmirror.c are compiled for the host, the S2C bank and the cart's memory as arrays,
and a driver prints the store counts and the bytes after each step. ZM_RTL_BREAK=1 runs the break
tests: each breaks one rule in a copy of the sources and requires a check here to fail."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
SOURCES = ["aud_state.h", "bmirror.h", "bmirror.c"]
YM, MODE, MS, MEM = 0x40, 0x60, 0x64, 0x100  # the fake cart's fields; regs 14..15 are sentinels

DRIVER = r"""
#include <stdio.h>
#include "bmirror.h"
static uint32_t s2c[32];
static uint8_t mem[MEM];
static void dump(const char* tag, uint32_t n) {
    printf("%s %u", tag, (unsigned)n);
    for (unsigned i = 0; i < AS_WORDS; i++) printf(" %u", (unsigned)s2c[S_AS + i]);
    for (unsigned i = 0; i < MEM; i++) printf(" %u", (unsigned)mem[i]);
    printf("\n");
}
static uint32_t frame(void) { aud_state r; return aud_state_read(s2c, &r) ? audio_mirror_frame(&r) : 999u; }
int main(void) {
    aud_state s = {.mode = 4, .ms = 12801};
    for (unsigned i = 0; i < 32; i++) s2c[i] = 0xA5A5A5A5u; /* an earlier run's words */
    for (unsigned i = 0; i < 16; i++) s.ym[i] = (uint8_t)(0x10 + i);
    mem[YM + 14] = 0xEE; mem[YM + 15] = 0xEF;
    audio_mirror_bind(mem, MEM, YM, MODE, MS);
    dump("unbooted", frame());
    aud_state_boot(s2c); dump("boot", 0);
    dump("publish", aud_state_publish(s2c, &s));
    dump("again", aud_state_publish(s2c, &s));
    dump("mirror", frame());
    dump("mirror_again", frame());
    s.ms += 17; s.ym[8] = 0x0F;
    dump("tick", aud_state_publish(s2c, &s));
    dump("mirror_tick", frame());
    audio_mirror_bind(mem, MEM, 0, MEM - 1, MS + 1); /* no YM; mode at the last byte; ms misaligned */
    s.mode = 1; s.ms = 5; s.ym[0] = 0x77; aud_state_publish(s2c, &s);
    dump("rebound", frame());
    audio_mirror_bind(mem, MEM, MEM - 4, MEM, MEM); /* all past the end */
    dump("outside", frame());
    audio_mirror_bind(mem, MEM, YM, MODE, MS); /* a stream (table 1.27): its counter rides the MS word */
    s.mode = 3; s.ms = 0; s.stream = 123456; aud_state_publish(s2c, &s);
    frame(); dump("stream", aud_state_stream(s2c));
    s.mode = 4; s.ms = 777; s.stream = 99; aud_state_publish(s2c, &s);
    frame(); dump("song", aud_state_stream(s2c));
    aud_stream_view v = {0};
    s.mode = 3; s.ms = 0; s.stream = 5000; aud_state_publish(s2c, &s); /* the old stream, then a restart */
    aud_stream_restart(&v, s2c);
    dump("restarted", aud_stream_read(&v, s2c));
    s.stream = 64; aud_state_publish(s2c, &s); /* BARD's first render of the new stream */
    dump("new_stream", aud_stream_read(&v, s2c));
    s.stream = 5000; aud_state_publish(s2c, &s); /* the new stream's count passes the old one's */
    dump("new_stream_on", aud_stream_read(&v, s2c));
    return 0;
}
"""


def run_driver(src: Path, work: Path) -> dict[str, tuple[int, list[int], list[int]]]:
    cc = shutil.which("cc")
    if not cc:
        pytest.skip("no host C compiler")
    (work / "drv.c").write_text(DRIVER)
    exe = work / "drv"
    defs = [f"-D{k}={v}" for k, v in (("YM", YM), ("MODE", MODE), ("MS", MS), ("MEM", MEM))]
    subprocess.run([cc, "-std=c11", "-Wall", "-Werror", *defs, "-I", str(src), "-o", str(exe),
                    str(work / "drv.c"), str(src / "bmirror.c")], check=True)  # fmt: skip
    out = subprocess.run([str(exe)], check=True, capture_output=True, text=True).stdout
    steps = {}
    for line in out.splitlines():
        tag, n, *rest = line.split()
        vals = [int(x) for x in rest]
        steps[tag] = (int(n), vals[:11], vals[11:])  # AS_WORDS (cycles/aud_state.h): 7 + the MP3 status (table 1.11)
    return steps


def ym(mem: list[int]) -> list[int]:
    return mem[YM : YM + 16]


def ms(mem: list[int]) -> int:
    return int.from_bytes(bytes(mem[MS : MS + 4]), "little")


def check_bank(st: dict) -> None:
    """BARD's side: a boot clears the block under its magic; a publish stores only what changed."""
    assert st["unbooted"][0] == 999, "a bank without the magic (an older sound image) must be ignored"
    _, words, _ = st["boot"]
    assert words == [0x31534D5A] + [0] * 10
    n, words, _ = st["publish"]
    assert words[1:3] == [4, 12801] and n == 6
    assert bytes(b for w in words[3:7] for b in w.to_bytes(4, "little")) == bytes(range(0x10, 0x20))
    assert words[7:] == [0, 0, 0, 0], "no MP3 stream: its status words stay 0"
    assert st["again"][0] == 0, "an unchanged state must cost BARD no store"
    assert st["tick"][0] == 2, "a tick: the position word and the one YM word that moved"


def check_cart(st: dict) -> None:
    """ZIGGY's side: the browser's fields, 14 registers, and nothing stored twice."""
    n, _, mem = st["mirror"]
    assert ym(mem) == [*range(0x10, 0x1E), 0xEE, 0xEF], "registers 0..13 only, as the worklet posts them"
    assert mem[MODE] == 4 and ms(mem) == 12801 and n == 14 + 1 + 1
    assert st["mirror_again"][0] == 0, "an unchanged state must cost the cart CPU no store"
    n, _, mem = st["mirror_tick"]
    assert n == 2 and ms(mem) == 12818 and ym(mem)[8] == 0x0F


def check_bind(st: dict) -> None:
    """A field the cart lacks, or one outside its memory, is never written."""
    n, _, mem = st["rebound"]
    assert ym(mem)[0] == 0x10, "an unbound YM block was written"
    assert mem[MEM - 1] == 1 and n == 1, "the mode byte at the memory's end, and nothing else"
    assert ms(mem) == 12818, "a misaligned song_ms was written"
    assert st["outside"][0] == 0


def check_stream(st: dict) -> None:
    """A stream's sample counter (zg.audioStreamPlayed, table 1.27) shares the MS word in mode 3 only: the
    cart reads it there, its song_ms reads 0 (no SNDH plays), and in any other mode the word is the ms."""
    n, words, mem = st["stream"]
    assert n == 123456 and words[1:3] == [3, 123456], "the stream's counter is not in the MS word"
    assert mem[MODE] == 3 and ms(mem) == 0, "a stream's counter reached the cart's song_ms"
    n, words, mem = st["song"]
    assert n == 0 and words[2] == 777 and ms(mem) == 777, "a song's ms was read as a stream counter"
    assert st["restarted"][0] == 0, "after a restart the old stream's count was read as the new one's"
    assert st["new_stream"][0] == 64 and st["new_stream_on"][0] == 5000, "the new stream's count was not read"


CHECKS = [check_bank, check_cart, check_bind, check_stream]


@pytest.fixture(scope="module")
def steps(tmp_path_factory: pytest.TempPathFactory) -> dict:
    return run_driver(FPGA / "cycles", tmp_path_factory.mktemp("mirror"))


@pytest.mark.parametrize("check", CHECKS, ids=[c.__name__ for c in CHECKS])
def test_the_mirror_follows_the_browsers_rules(steps: dict, check) -> None:  # noqa: ANN001 (a check)
    check(steps)


MUTANTS = [
    ("no_magic", "aud_state.h", "if (s2c[S_AS + AS_MAGIC_W] != AS_MAGIC) return 0;", ""),
    ("publish_always", "aud_state.h", "if (s2c[S_AS + i] != w[i]) {", "if (1) {"),
    ("all_16_regs", "bmirror.c", "put(m + g_at.ym, s->ym, AS_YM_REGS)", "put(m + g_at.ym, s->ym, 16)"),
    ("store_always", "bmirror.c", "if (dst[i] != src[i]) {", "{"),
    ("no_bounds", "bmirror.c", "return at && (uint64_t)at + len <= size ? at : 0u;", "return at;"),
    ("no_ms", "bmirror.c", "*ms = s->ms;", "(void)ms;"),
    ("no_stream_word", "aud_state.h", "s->mode == AS_MODE_STREAM ? s->stream : s->ms", "s->ms"),
    ("no_stale", "aud_state.h", "if (!v->fresh && w == v->stale) return 0;", ""),
    ("stream_as_ms", "aud_state.h", "w[AS_MODE_W] == AS_MODE_STREAM ? 0u : w[AS_MS_W]", "w[AS_MS_W]"),
]
BREAK = pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")


@BREAK
@pytest.mark.parametrize(("name", "file", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_mirror_rule_is_caught(tmp_path: Path, name: str, file: str, old: str, new: str) -> None:
    for f in SOURCES:
        shutil.copy2(FPGA / "cycles" / f, tmp_path / f)
    text = (tmp_path / file).read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique in {file}"
    (tmp_path / file).write_text(text.replace(old, new))
    st = run_driver(tmp_path, tmp_path)
    failed = []
    for check in CHECKS:
        try:
            check(st)
        except AssertionError:
            failed.append(check.__name__)
    assert failed, f"{name} went unnoticed"
