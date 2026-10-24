"""The board's picture against the browser's, frame for frame: the pixel oracle for a board change.

    uv run --with pyserial python tools/board_pic.py [--tty /dev/ttyUSB1] [--frames 150,300,600,900] cart...

Over the Linux console of a running glass (as board_fps.py): `glass ctl load` each disk, then, for
each frame N, freeze the firmware after frame N (the debug mailbox, cycles/bmailbox.h: `freeze`,
`frozen`), md5 the picture that frame PRESENTED (800x280 {R,G,B,0}; read through /dev/mem by
tools/board_pic_memcat.c, built here with `zig cc`), resume. The same frames of the native machine
(tools/video_dump.py + video_mix.py: the browser's picture) are hashed the same way; any frame that
differs fails (exit 1). A cart is deterministic in its frame count on both machines unless it reads
a clock or the music's position: run it twice on the board to tell (tcb_colorshock's frames are,
under the 3a firmware).
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

import video_dump
import video_mix
from linux_console import LinuxConsole

FPGA = Path(__file__).resolve().parent.parent
MB = 0x1FFF_FF00  # the mailbox: the cart window's last 256 bytes (DDR_CART_BASE 0x1E00_0000 + 32 MiB - 256)
DDR_CART = 0x1E00_0000  # glass/src/map.zig DDR_CART_BASE: the window under Linux
PIC_BYTES = 800 * 280 * 4
# Freeze after frame T, hash the picture it presented, resume (mailbox words: bmailbox.h).
PIC_SH = r"""B=%(mb)d
rd() { echo $(( $(devmem $(( B + $1 * 4 ))) )); }
for T in "$@"; do
  while [ $(rd 5) -lt $((T - 1)) ]; do :; done
  devmem $(( B + 13 * 4 )) 32 1
  while [ $(rd 14) -eq 0 ]; do :; done
  F=$(rd 14); P=$(rd 4); FB=$(rd $((2 + P)))
  S=$(/tmp/memcat $(( FB - $(rd 11) + %(ddr)d )) %(n)d | md5sum | cut -c1-32)
  echo "PIC $T $F $S"
  devmem $(( B + 13 * 4 )) 32 0
done
"""


def memcat() -> bytes:
    zig = os.environ.get("ZIG") or shutil.which("zig") or str(Path.home() / ".local/zig/0.16.0/zig")
    out = FPGA / "build" / "board_pic" / "memcat"
    out.parent.mkdir(parents=True, exist_ok=True)
    src = FPGA / "tools" / "board_pic_memcat.c"
    cmd = [zig, "cc", "-target", "arm-linux-musleabihf", "-static", "-Os", "-s", "-o", str(out), str(src)]
    subprocess.run(cmd, check=True)
    return out.read_bytes()


def push(c: LinuxConsole, data: bytes, path: str) -> None:
    """A file onto the board through the shell, base64 in short lines, checked by md5."""
    b = base64.b64encode(data).decode()
    c.run(f"rm -f {path}.b64")
    for i in range(0, len(b), 700):
        c.run(f"echo {b[i : i + 700]} >> {path}.b64")
    _, out = c.run(f"base64 -d {path}.b64 > {path} && rm {path}.b64 && chmod +x {path} && md5sum {path}")
    if hashlib.md5(data).hexdigest() not in out:
        sys.exit(f"board_pic: {path} arrived damaged")


def board(c: LinuxConsole, cart: str, frames: list[int]) -> dict[int, str]:
    rc, out = c.run(f"glass ctl load demo-{cart}.zmd", timeout=60)
    if rc:
        sys.exit(f"board_pic: load demo-{cart}.zmd: {out.strip()}")
    _, out = c.run("sh /tmp/board_pic.sh " + " ".join(map(str, frames)), timeout=60 + 2 * max(frames))
    got = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) == 4 and f[0] == "PIC" and f[1] == f[2]:  # frozen on the frame asked
            got[int(f[1])] = f[3]
    return got


def native(cart: str, frames: list[int]) -> dict[int, str]:
    subprocess.run(["make", "-s", "-C", str(FPGA), "host", f"CART={cart}"], check=True, capture_output=True)
    d = video_dump.dump(cart, frames)
    video_mix.mix(d, frames)
    out = {}
    for f in frames:
        m = (d / f"f{f}.mix").read_bytes()
        w = bytearray()
        for i in range(0, len(m), 3):
            w += m[i : i + 3] + b"\0"
        out[f] = hashlib.md5(w).hexdigest()
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--tty", default=os.environ.get("BOARD_TTY", "/dev/ttyUSB1"))
    ap.add_argument("--frames", default="150,300,600,900")
    ap.add_argument("carts", nargs="+")
    a = ap.parse_args()
    frames = [int(x) for x in a.frames.split(",")]
    c = LinuxConsole(a.tty)
    c.login()
    push(c, memcat(), "/tmp/memcat")
    script = PIC_SH % {"mb": MB, "ddr": DDR_CART, "n": PIC_BYTES}
    push(c, script.encode(), "/tmp/board_pic.sh")
    bad = 0
    for cart in a.carts:
        b, n = board(c, cart, frames), native(cart, frames)
        for f in frames:
            ok = b.get(f) == n[f]
            bad += not ok
            print(
                f"{cart} frame {f}: board {b.get(f, 'not frozen there')[:12]} browser {n[f][:12]} {'=' if ok else 'DIFFER'}"
            )
    print("board_pic:", "every frame equals the browser's" if not bad else f"{bad} frames DIFFER")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
