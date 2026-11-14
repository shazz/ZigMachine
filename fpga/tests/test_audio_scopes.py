"""The Paula scopes on the board (host/audio_scope.c, table 1.26, decisions.md 2026-11-14): the players'
`machinePaula*` calls rebuild what machine/audio/engine.zig's Channel.mixInto captures into `scope`, the
128 f32 a channel the browser's loader mirrors into the cart's zigos.scopes (music_debug's MOD, sample
and XM curves). On the board no CPU runs that mix (Paula is RTL), so before this they stayed flat.

- The value: (s / 128) * volume as f32 bits with no float op (BARD has no FPU), for every i8 sample and
  a spread of volumes, against the host's own f32 multiply.
- The scopes: the native oracle (sndh_oracle, ZM_SCOPE_CHECK=1) runs the machine's engine beside the
  rebuild and holds them word for word after every render, for a MOD, the 12517 Hz sample, an XM and
  a MOD whose samples loop.
- Where they go: the cart's field only if it is 4 x 128 f32 inside its memory (cycles/bmirror.c), and
  BARD writes only inside the cart's data (cycles/bscope.h).

ZM_RTL_BREAK=1 runs the break tests: each breaks one rule in a copy of audio_scope.c, relinks the oracle
with it, and the word-for-word check must fail on at least one song."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest
from host_make import make_host

FPGA = Path(__file__).resolve().parent.parent
ORACLE = FPGA / "build/host/oracle/sndh_oracle"
SONGS = ["lollapalooza.mod", "smp1.raw", "keygen_9000.xm"]  # music_debug's keys 1, 3 and 5
LOOPED = "chcknbnk.mod"  # its samples reach their loops within FRAMES (the three above never do)
FRAMES = 300
CC = shutil.which("cc") or "cc"


@pytest.fixture(scope="module")
def oracle() -> Path:
    make_host("memmap", str(ORACLE.relative_to(FPGA)))
    return ORACLE


def scope_check(exe: Path, song: str) -> dict[str, int]:
    out = subprocess.run([str(exe), song, "0", str(FRAMES)], env={**os.environ, "ZM_SCOPE_CHECK": "1"},
                         check=True, capture_output=True, text=True).stdout  # fmt: skip
    m = re.search(r"^ZM SCOPE renders (\d+) diff (\d+) live (\d+) moved (\d+)$", out, re.MULTILINE)
    assert m, out[-2000:]
    return dict(zip(("renders", "diff", "live", "moved"), map(int, m.groups()), strict=True))


@pytest.mark.parametrize("song", [*SONGS, LOOPED])
def test_the_rebuilt_scopes_are_the_engines_word_for_word(oracle: Path, song: str) -> None:
    got = scope_check(oracle, song)
    assert got["renders"] == FRAMES and got["diff"] == 0
    assert got["live"] > FRAMES * 3 // 4 and got["moved"] > FRAMES * 3 // 4, f"{song}: the scope never moved: {got}"


F32_DRIVER = r"""
#include <stdio.h>
#include <string.h>
#include "audio_scope.h"
static const float VOLS[] = {1.0f, 0.0f, -0.0f, 0.9f, 0.9375f, 0.5f, 63.0f / 64.0f, 1.0f / 64.0f, 0.3333333f,
                             1.9960938f, 0.73f, 1e-3f, 1e-30f, 1e-38f, 7.0f, -0.6f, 0.123456789f, 0.99999994f};
int main(void) {
    unsigned bad = 0, n = 0;
    for (unsigned v = 0; v < sizeof VOLS / sizeof VOLS[0]; v++)
        for (int s = -128; s < 128; s++, n++) {
            volatile float want = (float)s * (1.0f / 128.0f) * VOLS[v];
            float vol = VOLS[v], w = want;
            uint32_t vb, wb;
            memcpy(&vb, &vol, 4), memcpy(&wb, &w, 4);
            if ((wb & 0x7F800000u) == 0) wb &= 0x80000000u; /* a denormal product: the rebuild gives a zero */
            if (zsc_f32(s, vb) != wb) {
                if (bad++ < 5) printf("bad s %d vol %g got %08x want %08x\n", s, (double)vol, zsc_f32(s, vb), wb);
            }
        }
    printf("checked %u bad %u\n", n, bad);
    return 0;
}
"""


def test_the_f32_product_rounds_as_the_hosts_multiply(tmp_path: Path) -> None:
    (tmp_path / "drv.c").write_text(F32_DRIVER)
    exe = tmp_path / "drv"
    subprocess.run([CC, "-std=c11", "-O1", "-ffp-contract=off", "-Wall", "-Werror", "-I", str(FPGA / "host"), "-o",
                    str(exe), str(tmp_path / "drv.c"), str(FPGA / "host/audio_scope.c")], check=True)  # fmt: skip
    out = subprocess.run([str(exe)], check=True, capture_output=True, text=True).stdout
    assert out.strip().endswith("checked 4608 bad 0"), out


BIND_DRIVER = r"""
#include <stdio.h>
#include "bmirror.h"
static uint8_t mem[4096];
int main(void) {
    const uint32_t at[] = {0, 512, 514, 2048, 2052, 4096};
    for (unsigned i = 0; i < 6; i++) {
        audio_mirror_scopes(mem, sizeof mem, at[i]);
        uint32_t got = audio_mirror_scopes_at();
        printf("%u %ld\n", (unsigned)at[i], got ? (long)(uint32_t)(got - (uint32_t)(uintptr_t)mem) : -1L); /* mod 2^32 */
    }
    return 0;
}
"""


def test_only_a_whole_aligned_field_inside_the_cart_is_taken(tmp_path: Path) -> None:
    (tmp_path / "drv.c").write_text(BIND_DRIVER)
    exe = tmp_path / "drv"
    subprocess.run([CC, "-std=c11", "-Wall", "-Werror", "-I", str(FPGA / "cycles"), "-o", str(exe),
                    str(tmp_path / "drv.c"), str(FPGA / "cycles/bmirror.c")], check=True)  # fmt: skip
    out = subprocess.run([str(exe)], check=True, capture_output=True, text=True).stdout.split()
    got = dict(zip(out[0::2], out[1::2], strict=True))
    assert got == {"0": "-1", "512": "512", "514": "-1", "2048": "2048", "2052": "-1", "4096": "-1"}


def test_bard_writes_only_inside_the_carts_data() -> None:
    src = (FPGA / "cycles/bscope.h").read_text()
    assert "at >= SND_BASE + SND_IMAGE_MAX && at <= SND_CART_END - ZSC_BYTES" in src
    mbox = (FPGA / "cycles/snd_mailbox.h").read_text()
    assert "#define SND_CART_END 0x41C00000u" in mbox
    assert "__ram=0x41C00000" in (FPGA / "cycles/sound.mk").read_text(), "BARD's RAM moved: SND_CART_END must follow"
    words = [int(w) for w in re.findall(r"C_\w+ = (\d+)", mbox)]
    assert words.count(7) == 1, "C_SCOPES must be a C2S word no command uses"


MUTANTS = [
    ("ctr_reset_on_trigger", "c->pos = 0, c->active = 1;", "c->pos = 0, c->active = 1, c->ctr = 0;"),
    ("no_rounding", "if (rem > half || (rem == half && (m & 1u))) m++;", "(void)half;"),
    ("fast_path_past_the_piece", "if (n - i >= 4u && p + step3 < end) {", "if (p + step3 < end) {"),
    ("no_volume", "if (!c->tab_ok) build_tab(c);", "vol_split(c, 0x3F800000u), build_tab(c);"),
    ("stale_volume_table", "    c->tab_ok = 0;\n", ""),
    ("no_loop", "do p -= span; while (p >= end);", "c->active = 0; break;"),
]
BREAK = pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")


def mutant_oracle(tmp: Path, old: str, new: str) -> Path:
    """The oracle relinked with a copy of audio_scope.c where `old` became `new`."""
    text = (FPGA / "host/audio_scope.c").read_text()
    assert text.count(old) == 1, f"the text to break is not unique: {old}"
    (tmp / "audio_scope.c").write_text(text.replace(old, new))
    obj = tmp / "audio_scope.o"
    subprocess.run([CC, "-std=c11", "-O2", "-I", str(FPGA / "host"), "-c", str(tmp / "audio_scope.c"), "-o", str(obj)],
                   check=True)  # fmt: skip
    objs = [p for p in sorted((ORACLE.parent / "o").glob("*.o")) if p.name != "audio_scope.o"]
    common = FPGA / "build/host/common"
    rt = [common / n for n in ("rt.o", "rt-mem.o", "rt-exc.o", "aplayer.o", "maud.o")]
    exe = tmp / "sndh_oracle"
    subprocess.run([CC, *map(str, objs), str(obj), *map(str, rt), "-lm", "-lpthread", "-o", str(exe)], check=True)
    return exe


@BREAK
@pytest.mark.parametrize(("name", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_scope_rule_is_caught(oracle: Path, tmp_path: Path, name: str, old: str, new: str) -> None:
    exe = mutant_oracle(tmp_path, old, new)
    diffs = {song: scope_check(exe, song)["diff"] for song in [*SONGS, LOOPED]}
    assert any(diffs.values()), f"{name} went unnoticed: {diffs}"
