"""Run shell commands on the board's Linux console over serial and print their output.

    uv run --with pyserial python prototypes/lut_diet/serial_cmd.py --tty /dev/ttyUSB1 'md5sum /mnt/sd/zigmachine.bit' ...
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "fpga/tools"))
from linux_console import LinuxConsole  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tty", default="/dev/ttyUSB1")
    ap.add_argument("--timeout", type=float, default=20.0)
    ap.add_argument("cmds", nargs="+")
    a = ap.parse_args()
    con = LinuxConsole(a.tty)
    con.login()
    for c in a.cmds:
        rc, out = con.run(c, timeout=a.timeout)
        print(f"$ {c}  -> {rc}\n{out.strip()}")


main()
