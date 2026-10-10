"""Send a file to U-Boot's `loadx` (XMODEM-1K) over the Z7-Lite's CH340 console,
so a firmware image reaches DDR without taking the SD card out.

    uv run --with xmodem --with pyserial python tools/uboot_loadx.py build/hcycles/board/tutorial/fw.bin 0x04000000

It types `loadx <addr>` (the console already runs at 921600), waits for the receiver's first 'C', sends the file and
prints U-Boot's reply (it reports the byte count, rounded up to 1 KiB blocks).
The port is the CH340 (UBOOT_TTY overrides), as tools/uboot.sh uses it.
"""

from __future__ import annotations

import glob
import os
import sys
import time

import serial
from xmodem import XMODEM1k

BAUD = 921600


def main() -> int:
    path, addr = sys.argv[1], sys.argv[2]
    tty = os.environ.get("UBOOT_TTY") or os.path.realpath(glob.glob("/dev/serial/by-id/*1a86*")[0])
    port = serial.Serial(tty, BAUD, timeout=2)
    port.reset_input_buffer()
    port.write(f"loadx {addr}\r".encode())
    time.sleep(0.5)
    port.reset_input_buffer()  # the echo and "## Ready for binary (xmodem) download"
    modem = XMODEM1k(lambda n, timeout=2: port.read(n) or None, lambda data, timeout=2: port.write(data))
    with open(path, "rb") as f:
        ok = modem.send(f, retry=32)
    time.sleep(0.5)
    print(port.read(4096).decode(errors="replace").replace("\r", ""))
    print(f"uboot_loadx: {'sent' if ok else 'FAILED'} {os.path.getsize(path)} bytes to {addr}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
