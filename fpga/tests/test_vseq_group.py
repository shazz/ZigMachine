"""cycles/vseq_group.c with handler planes in a group, compiled for the host against fakes of the
board (the compositor's commands, the region's halfwords, the HBL dispatch) and an RTL model of
the overscan flicker test (zm_video_plane.v: a pass flickers when RES_FLICKER differs from what
that plane's pass before saw; LATCH takes it). video.zig's answer is "the plane's OWN handler
bumped it on this line" (renderPlaneOverscan); the test drives three overscan planes whose
handlers flicker on different lines (every line, the border bands only, never) and checks every
pass's flicker, the order of handlers and passes, the group bits, and RES_FLICKER after the group.
ZM_RTL_BREAK=1: the firmware's RES_FLICKER store left out (VSEQ_BREAK_FLICKER) must be caught."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import video_dump  # tools/ is on the path only from here

FAKES = {
    "host.h": "#pragma once\n#include <stdint.h>\nstruct w2c_env { int unused; };\ntypedef uint32_t u32;\n",
    "vboard.h": "#pragma once\n#include <stdint.h>\n"
    "enum { ZMV_BG, ZMV_PLANE, ZMV_LATCH, ZMV_MIX, ZMV_PRESENT, ZMV_CLEAR, ZMV_WB };\n"
    "enum { ZMV_HOLD = 1, ZMV_KEEP = 2, ZMV_NOPFB = 4 };\n"
    "static inline uint32_t zmv_reg(int w) { (void)w; return 0; }\n"
    "static inline void zmv_flush_dcache(void) {}\n",
    "vseq_wait.h": '#pragma once\n#include "host.h"\n#include "vseq.h"\n'
    "void t_hbl(uint16_t id, u32 p, u32 y, u32 pos);\n"
    "static inline void hbl(struct w2c_env* e, uint16_t id, u32 p, u32 y, u32 pos) { (void)e; t_hbl(id, p, y, pos); }\n"
    "static inline int decide(int y) { return vseq_decide(y); }\n",
}

DRIVER = r"""
#include <stdio.h>
#include <string.h>
#include "vseq.h"
#include "zm_memmap.h"
#define H ZM_RASTER_HEIGHT
static uint8_t g_reg[0x80];
static uint16_t seen[4];
static int mode[4] = {ZM_FB_MODE_OVERSCAN, ZM_FB_MODE_OVERSCAN, ZM_FB_MODE_OVERSCAN, ZM_FB_MODE_NORMAL};
static int bumped[4][H], bad, painted_waits;
const uint8_t* vseq_skip;
int (*vseq_decide)(int y);
uint16_t vseq_r16(uint32_t off) { uint16_t v; memcpy(&v, g_reg + off, 2); return v; }
void vseq_w16(uint32_t off, uint16_t v) { memcpy(g_reg + off, &v, 2); }
static uint16_t flick(void) { return vseq_r16(ZM_REG_RES_FLICKER); }
/* Plane 0 flickers every line, plane 1 in the border bands, plane 2 has no handler. */
static int flickers(int p, int y) { return p == 0 || (p == 1 && (y < 40 || y >= 240)); }
void t_hbl(uint16_t id, u32 p, u32 y, u32 pos) {
    printf("H %u %u %u %u\n", id, p, y, pos);
    if (flickers((int)p, (int)y)) vseq_w16(ZM_REG_RES_FLICKER, (uint16_t)(flick() + 1)), bumped[p][y] = 1;
}
void vseq_issue(int op, int plane, int line, int mix, int first, int fill, int ext) {
    int f = flick() != seen[plane];  /* zm_video_plane.v */
    seen[plane] = flick();
    if (mode[plane] == ZM_FB_MODE_OVERSCAN && f != bumped[plane][line]) bad++;
    printf("I %d %d %d %d %d %d %d\n", op, plane, line, mix, first, fill, ext);
}
void vseq_latch(int p) { seen[p] = flick(); printf("L %d\n", p); }
int vseq_fill(void) { return 1; }
void vseq_wait_painted(void) { painted_waits++; }
void vseq_wait_swap(void) {}
void vseq_idle(void) {}
int vseq_plane_handler(int p) { return vseq_r16(ZM_REG_FB_HBL_ID + 2u * (uint32_t)p) != 0; }
uint8_t vseq_plane_mode(int p) { return (uint8_t)mode[p]; }
void vseq_plane_lines(int p, uint32_t* oy, uint32_t* rows) { (void)p; *oy = 0, *rows = H; }
int main(void) {
    vseq_w16(ZM_REG_RES_FLICKER, 0xFFF0); /* wraps through 0 */
    vseq_w16(ZM_REG_FB_HBL_ID, 1), vseq_w16(ZM_REG_FB_HBL_ID + 2, 2);
    vseq_w16(ZM_REG_FB_HBL_POS, 7), vseq_w16(ZM_REG_FB_HBL_POS + 2, 9);
    struct w2c_env e;
    vseq_group(&e, 0x7, 1, 1);
    int total = 0;
    for (int p = 0; p < 4; p++) for (int y = 0; y < H; y++) total += bumped[p][y];
    printf("BAD %d FINAL %u WANT %u WAITS %d\n", bad, flick(), (unsigned)(uint16_t)(0xFFF0 + total), painted_waits);
    mode[2] = ZM_FB_MODE_MEDIUM;
    printf("OK %d %d\n", vseq_group_ok(0x7), vseq_group_ok(0x4));
    return 0;
}
"""


def run(d: Path, *defines: str) -> list[str]:
    cc = shutil.which("cc")
    if not cc:
        pytest.skip("no host C compiler")
    for name, text in FAKES.items():
        (d / name).write_text(text)
    for src in ("vseq_group.c", "vseq.h"):  # beside the fakes: their quoted includes find these first
        shutil.copy(FPGA / "cycles" / src, d / src)
    (d / "drv.c").write_text(DRIVER)
    inc = video_dump.memmap_header().parent
    exe = d / "drv"
    subprocess.run([cc, "-std=c11", "-Wall", "-Werror", *defines, "-I", str(d), "-I", str(inc), "-o", str(exe),
                    str(d / "drv.c"), str(d / "vseq_group.c")], check=True)  # fmt: skip
    return subprocess.run([str(exe)], check=True, capture_output=True, text=True).stdout.splitlines()


def expected_order(lines: int) -> list[str]:
    """LATCH 0..2, then per line: plane 0's handler and pass, plane 1's, plane 2's pass (no handler)."""
    out = [f"L {p}" for p in range(3)]
    for y in range(lines):
        out += [
            f"H 1 0 {y} 7",
            f"I 1 0 {y} 1 1 1 {2}",
            f"H 2 1 {y} 9",
            f"I 1 1 {y} 1 0 0 {1 | 2}",
            f"I 1 2 {y} 1 0 0 {1 | 4}",
        ]
    return out


def test_handler_group_flickers_as_video_zig(tmp_path: Path) -> None:
    out = run(tmp_path)
    tail = dict(zip(out[-2].split()[0::2], out[-2].split()[1::2]))
    assert out[:-2] == expected_order(280)
    assert tail["BAD"] == "0"
    assert tail["FINAL"] == tail["WANT"]  # the handlers' own count, as video.zig leaves it
    assert int(tail["WAITS"]) == 2 * 280 - 1  # every handler after the pass before has painted
    assert out[-1] == "OK 0 1"  # a medium plane beside a handler plane is no group


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
def test_break_flicker_store(tmp_path: Path) -> None:
    out = run(tmp_path, "-DVSEQ_BREAK_FLICKER")
    assert int(out[-2].split()[1]) > 0
