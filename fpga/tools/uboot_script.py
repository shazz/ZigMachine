"""boot.cmd -> boot.scr without mkimage (glass_sd.py stages it; glass/boot/build_planA.sh too).

    uv run python tools/uboot_script.py BOOT_CMD OUT_SCR

Kept apart from glass_sd.py so a script can make boot.scr without the shelf's generated modules.
"""

from __future__ import annotations

import argparse
import struct
import time
import zlib
from pathlib import Path

IH_MAGIC, IH_OS_LINUX, IH_ARCH_ARM, IH_TYPE_SCRIPT = 0x27051956, 5, 2, 6


def script_image(text: bytes, name: str, epoch: int) -> bytes:
    """A U-Boot legacy script image, as `mkimage -A arm -O linux -T script -C none` makes."""
    data = struct.pack(">II", len(text), 0) + text
    head = struct.pack(">IIIIIIIBBBB32s", IH_MAGIC, 0, epoch, len(data), 0, 0, zlib.crc32(data), IH_OS_LINUX,
                       IH_ARCH_ARM, IH_TYPE_SCRIPT, 0, name.encode()[:32])  # fmt: skip
    head = head[:4] + struct.pack(">I", zlib.crc32(head)) + head[8:]
    return head + data


def script_text(cmd: bytes) -> bytes:
    """boot.cmd without its comments or blank lines: zeST's U-Boot (old hush) read a comment's
    apostrophe as an open quote, a `syntax error` that skipped the whole script (2026-10-10)."""
    lines = [ln.strip() for ln in cmd.decode("ascii").splitlines()]
    return "".join(ln + "\n" for ln in lines if ln and not ln.startswith("#")).encode()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("cmd", type=Path, help="the U-Boot script source (fpga/glass/boot/boot.cmd)")
    p.add_argument("out", type=Path, help="the boot.scr to write")
    a = p.parse_args()
    a.out.write_bytes(script_image(script_text(a.cmd.read_bytes()), "zigmachine", int(time.time())))


if __name__ == "__main__":
    main()
