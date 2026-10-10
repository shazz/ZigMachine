"""The cart / diag-mode half of a board run (MORNING.md 2a, 2b): mailbox resets, RUN, polling and
the expected result rows. Addresses are DDR as U-Boot sees them (the firmware's debug mailbox,
cycles/bmailbox.h, and the diag buffers)."""

from __future__ import annotations

import time
from pathlib import Path

import uboot_serial as us
from uboot_serial import UBoot

CTRL = 0x43C00008
CART_STATE = 0x43C00010
MB_MAGIC, MB_MODE, MB_CFG = 0x05FFFE00, 0x05FFFE04, 0x05FFFE08
MB_FRAMES = 0x05FFFF14  # mailbox word 5 (bmailbox.h)
MB_CLEAR = 0x05FFFF00  # 16 words
ROW = 0x05F01100  # the video DMA's row (mode 3 target, mode 4 PFB source)
RES = 0x05F80000  # the compositor's result rows
PROBE = 0x05F80C00
GAID = 0x47414944  # "GAID": the diag magic
PREFILL = str(Path(__file__).resolve().parent.parent / "build" / "board_hp" / "diag4_prefill.txt")


def expected(mode: int) -> dict[int, list[int]]:
    """Address -> the words that must read there when a diag pass is done (MORNING.md 2b)."""
    if mode == 3:
        return {ROW: [0x55667788] * 8, RES: [0x002C3239] * 8}
    probe = [0xFF040404, 0xFF030303, 0xFF020202, 0xFF010101] * 2
    return {RES: [i * 0x010101 for i in range(1, 0x21)], PROBE: probe}


def start_cart(con: UBoot) -> None:
    con.mw(MB_MAGIC, 0)
    con.mw(MB_CFG, 0)
    con.mw(MB_CLEAR, 0, 0x10)
    con.mw(CTRL, 1)


def start_diag(con: UBoot, mode: int, hp_cfg: int = 0, prefill: str = PREFILL) -> None:
    con.mw(CTRL, 0)
    time.sleep(us.PAUSE)
    con.mw(RES, 0xEEEEEEEE, 0x400)
    con.mw(PROBE, 0, 8)
    if mode == 3:
        con.mw(ROW, 0xEEEEEEEE, 0x400)
    else:
        for line in Path(prefill).read_text().splitlines():
            con.cmd(line.strip())
    con.mw(MB_MAGIC, GAID)
    con.mw(MB_MODE, mode)
    con.mw(MB_CFG, 0xC0F00000 | hp_cfg)
    con.mw(CTRL, 1)


def poll_diag(con: UBoot, mode: int, secs: float) -> tuple[bool, str]:
    """Done = CART_STATE 0x<mode>44, CART_BEAT <mode>. 0x<mode>40 with a `5A<wait#><STATUS>` beat = hung."""
    end = time.monotonic() + secs
    while True:
        state, beat = con.md(CART_STATE, 2)
        if state == (mode << 8 | 0x44) and beat == mode:
            return True, f"done state={state:#x} beat={beat:#x}"
        if time.monotonic() > end:
            hung = state == (mode << 8 | 0x40) and beat >> 16 == 0x5A
            tail = f" (HUNG in wait {beat >> 8 & 0xFF:#x}, AXI STATUS {beat & 0xFF:#x})" if hung else ""
            return False, f"not done: state={state:#x} beat={beat:#x}{tail}"
        time.sleep(0.2)


def compare_rows(con: UBoot, mode: int) -> list[str]:
    """One line per mismatching region, empty when every row is as expected."""
    bad = []
    for addr, want in expected(mode).items():
        got = con.md(addr, len(want))
        if got != want:
            first = next(i for i, (g, w) in enumerate(zip(got, want, strict=True)) if g != w)
            bad.append(f"{addr:#x}+{4 * first:#x}: got {got[first]:08x} want {want[first]:08x}")
    return bad


def poll_cart(con: UBoot, secs: float) -> tuple[bool, str]:
    """Running = CART_STATE 2 and CART_BEAT advancing; FRAMES is reported as info only."""
    _, beat0 = con.md(CART_STATE, 2)
    frames0 = con.md(MB_FRAMES, 1)[0]
    time.sleep(secs)
    state, beat = con.md(CART_STATE, 2)
    frames = con.md(MB_FRAMES, 1)[0]
    note = f"state={state:#x} beat {beat0:#x}->{beat:#x} frames {frames0}->{frames}"
    return state == 2 and beat != beat0, note
