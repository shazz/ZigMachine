"""A screenshot of the board from U-Boot: read the firmware's debug mailbox
(fpga/cycles/bmailbox.h, PS DDR 0x05ffff00), freeze the cart after a whole frame,
dump the shown picture (or the machine's PFB) with `md.l`, write .bin + .png.

    sg dialout -c "uv run --with pyserial python tools/board_shot.py --out build/shots/tut"
    ... --what pfb                  the PFB as the machine wrote it (scene_hash's bytes)
    ... --what pfb --expect f.bin   and compare it pixel for pixel with an expected PFB dump

Needs `dcache off` at the U-Boot prompt first (the ARM must read DDR, not its
cache). About 900 KB of picture is ~3.4 MB of console text: ~40 s at 921600.
The console (CH340, UBOOT_TTY overrides) is driven here directly, as
tools/uboot_loadx.py does: tools/uboot.sh's fixed waits cannot tell when a long
`md` has ended, this waits for the prompt.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys
import time

import serial

from board_md import parse_md, png_rgb, words_to_bytes

MB_DDR = 0x05FFFF00
MB_MAGIC = 0x424D4D5A
MB = ["magic", "version", "fb0", "fb1", "presented", "frames", "pfb", "pfb_w", "pfb_h", "pic_w", "pic_h",
      "cpu_base", "ddr_base", "freeze", "frozen", "front"]  # fmt: skip
PROMPT = "Zynq> "
CHUNK = 0x400  # words a request: 256 lines


class Console:
    def __init__(self, tty: str) -> None:
        self.port = serial.Serial(tty, 921600, timeout=0.2)

    def cmd(self, line: str, timeout: float = 20.0) -> str:
        self.port.reset_input_buffer()
        self.port.write(f"{line}\r".encode())
        buf, end = b"", time.monotonic() + timeout
        while time.monotonic() < end:
            buf += self.port.read(65536)
            if buf.rstrip(b" ").endswith(PROMPT.strip().encode()) and len(buf) > len(line):
                break
        return buf.decode(errors="replace")

    def words(self, ddr: int, n: int, tries: int = 6) -> list[int]:
        out: list[int] = []
        for at in range(ddr, ddr + 4 * n, 4 * CHUNK):
            k = min(CHUNK, n - (at - ddr) // 4)
            for _ in range(tries):
                got = parse_md(self.cmd(f"md.l {at:x} {k:x}"), at, k)
                if got is not None:
                    break
            else:
                sys.exit(f"board_shot: {at:#x} unreadable after {tries} tries")
            out += got
        return out


def mailbox(con: Console) -> dict[str, int]:
    mb = dict(zip(MB, con.words(MB_DDR, len(MB)), strict=True))
    if mb["magic"] != MB_MAGIC:
        sys.exit(f"board_shot: no mailbox at {MB_DDR:#x} (magic {mb['magic']:#x}): is the mailbox firmware running?")
    return mb


def freeze(con: Console, on: bool) -> dict[str, int]:
    con.cmd(f"mw.l {MB_DDR + 4 * MB.index('freeze'):x} {int(on)}")
    for _ in range(50):
        mb = mailbox(con)
        if (mb["frozen"] != 0) == on:
            return mb
        time.sleep(0.1)
    sys.exit(f"board_shot: the firmware did not {'freeze' if on else 'resume'} (CART_STATE at 0x43c00010?)")


def ddr(mb: dict[str, int], cpu_addr: int) -> int:
    return cpu_addr - mb["cpu_base"] + mb["ddr_base"]


def compare(got: bytes, path: str, width: int) -> None:
    want = open(path, "rb").read()
    bad = [i // 4 for i in range(0, min(len(got), len(want)), 4) if got[i : i + 3] != want[i : i + 3]]
    print(f"board_shot: {len(bad)} of {len(want) // 4} pixels differ from {path}")
    for p in bad[:12]:
        print(f"  x={p % width} y={p // width} got {got[4 * p : 4 * p + 4].hex()} want {want[4 * p : 4 * p + 4].hex()}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", default="build/shots/shot", help="path prefix for .bin / .png")
    ap.add_argument("--what", choices=["picture", "fb0", "fb1", "pfb"], default="picture")
    ap.add_argument("--expect", help="an expected dump of the same thing to compare with")
    ap.add_argument("--keep-frozen", action="store_true", help="leave the cart frozen")
    a = ap.parse_args()
    tty = os.environ.get("UBOOT_TTY") or os.path.realpath(glob.glob("/dev/serial/by-id/*1a86*")[0])
    con, t0 = Console(tty), time.monotonic()
    mb = freeze(con, True)
    print("board_shot: mailbox " + " ".join(f"{k}={v:#x}" for k, v in mb.items()))
    which = {"picture": "fb1" if mb["front"] else "fb0"}.get(a.what, a.what)
    w, h = (mb["pfb_w"], mb["pfb_h"]) if which == "pfb" else (mb["pic_w"], mb["pic_h"])
    data = words_to_bytes(con.words(ddr(mb, mb[which]), w * h))
    if not a.keep_frozen:
        freeze(con, False)
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    open(f"{a.out}.{which}.bin", "wb").write(data)
    png_rgb(f"{a.out}.{which}.png", w, h, data)
    print(f"board_shot: {which} {w}x{h} of frame {mb['frozen']} -> {a.out}.{which}.png ({time.monotonic() - t0:.0f} s)")
    if a.expect:
        compare(data, a.expect, w)
    return 0


if __name__ == "__main__":
    sys.exit(main())
