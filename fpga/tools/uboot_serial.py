"""The U-Boot console (CH340 at 921600) as a library, for board_preflight.py / board_run.py.

Unlike tools/uboot.sh (fixed waits) every command here waits for the `Zynq>` prompt, so a
missing prompt is an error, not a silent empty reply. `md.l` replies go through board_md.parse_md.
"""

from __future__ import annotations

import glob
import os
import re
import subprocess
import time
from pathlib import Path

import serial
from board_md import parse_md

BAUD = 921600
PROMPT = b"Zynq>"
ID_HPTEST = 0x48505431
INTERRUPT_LIMIT = 10.0  # [s of Ctrl-Cs before giving up; tests shorten]
PAUSE = 1.0  # [s: the video DMA's last burst; tests set 0]
# HP3 too: the sound CPU writes its memory there (--sound-cpu); with the reset 64-bit write channel
# the upper half of every store is dropped and the music never plays (2026-10-10). The PCM reader
# that shares HP3 only reads, so 32-bit writes cost it nothing on any bitstream.
AFI_WIDTHS = (
    "mw.l 0xf8008000 0; mw.l 0xf8008014 0xf01; mw.l 0xf8009000 0; mw.l 0xf8009014 0xf01; "
    "mw.l 0xf800b000 0; mw.l 0xf800b014 0xf01"
)
AFI_HP2_WIDTH = "mw.l 0xf800a000 0; mw.l 0xf800a014 0xf01"  # the blitter's port, --blit bitstreams only
CRC = re.compile(r"==>\s*([0-9a-f]{8})\s*$", re.MULTILINE)


class UBootError(RuntimeError):
    """The console did not answer as U-Boot would (no prompt, garbled md, bad crc line)."""


def default_tty() -> str:
    found = glob.glob("/dev/serial/by-id/*1a86*")
    if not found:
        raise UBootError("no CH340 console (/dev/serial/by-id/*1a86*); set UBOOT_TTY")
    return os.path.realpath(found[0])


class UBoot:
    def __init__(self, tty: str | None = None, timeout: float = 5.0) -> None:
        self.port = serial.Serial(tty or os.environ.get("UBOOT_TTY") or default_tty(), BAUD, timeout=0.05)
        self.timeout = timeout

    def _read_until_prompt(self, timeout: float) -> str:
        buf, end = b"", time.monotonic() + timeout
        while time.monotonic() < end:
            buf += self.port.read(65536)
            if buf.rstrip(b" \r\n").endswith(PROMPT):
                return buf.decode(errors="replace").replace("\r", "")
        raise UBootError(f"no `Zynq>` prompt within {timeout:g} s (got {buf[-80:]!r})")

    def interrupt(self, limit: float | None = None) -> None:
        """Ctrl-C every 0.1 s until the prompt: autoboot's network retry loop eats a single one."""
        limit = INTERRUPT_LIMIT if limit is None else limit
        end = time.monotonic() + limit
        while time.monotonic() < end:
            self.port.write(b"\x03")
            time.sleep(0.1)
            if PROMPT in self.port.read(65536):
                time.sleep(0.2)
                self.port.reset_input_buffer()
                return
        raise UBootError(f"no U-Boot prompt after Ctrl-C for {limit:g} s: is the board on, console at {BAUD}?")

    def cmd(self, line: str, timeout: float | None = None) -> str:
        self.port.reset_input_buffer()
        self.port.write(f"{line}\r".encode())
        return self._read_until_prompt(timeout or self.timeout)

    def mw(self, addr: int, val: int, count: int | None = None) -> None:
        self.cmd(f"mw.l {addr:x} {val:x}" + (f" {count:x}" if count else ""))

    def md(self, addr: int, n: int = 1, tries: int = 4) -> list[int]:
        for _ in range(tries):
            words = parse_md(self.cmd(f"md.l {addr:x} {n:x}"), addr, n)
            if words is not None:
                return words
        raise UBootError(f"md.l {addr:#x} {n:#x} unreadable after {tries} tries")

    def crc32(self, addr: int, size: int) -> int:
        m = CRC.search(self.cmd(f"crc32 {addr:x} {size:x}", timeout=15))
        if not m:
            raise UBootError(f"crc32 {addr:#x} {size:#x}: no result line")
        return int(m.group(1), 16)

    def loadx(self, path: str, addr: int) -> None:
        """XMODEM-1K upload (~25 s for 230 KB); same protocol as uboot_loadx.py, on this port."""
        from xmodem import XMODEM1k  # [lazy: only the upload needs the package]

        self.port.reset_input_buffer()
        self.port.write(f"loadx {addr:x}\r".encode())
        time.sleep(0.5)
        self.port.reset_input_buffer()
        modem = XMODEM1k(lambda n, timeout=2: self.port.read(n) or None, lambda d, timeout=2: self.port.write(d))
        with open(path, "rb") as f:
            if not modem.send(f, retry=32):
                raise UBootError(f"loadx of {path} failed")
        self._read_until_prompt(10)


def load_pl(bit: str) -> None:
    """Program the PL over the Digilent HS2 JTAG; raises on a non-zero exit."""
    r = subprocess.run(["openFPGALoader", "-c", "digilent_hs2", bit], capture_output=True, text=True, check=False)
    if r.returncode:
        raise UBootError(f"openFPGALoader {bit} failed ({r.returncode}): {r.stderr.strip()[-200:]}")
    PL_STATE.parent.mkdir(parents=True, exist_ok=True)
    PL_STATE.write_text(bit + "\n")


# The last bitstream this tool loaded. A bitstream with nothing behind GP0 (the YM, HDMI, EDID and blink
# tests) makes any 0x43c0_xxxx access hang the ARM until RST KEY (2026-10-09), so quiesce skips CTRL then.
PL_STATE = Path(__file__).resolve().parent.parent / "build" / ".board_pl"
NO_GP0 = ("ym_test", "hdmi_test", "hdmi_audio", "edid_test", "blink")


def pl_has_gp0() -> bool:
    """False when the last bitstream loaded through load_pl has no GP0 slave; True when unknown."""
    last = PL_STATE.read_text().strip() if PL_STATE.exists() else ""
    return not any(tag in last for tag in NO_GP0)


def quiesce(con: UBoot) -> None:
    """CTRL.RUN off and a second for the video DMA's last burst, BEFORE any reload (a cut burst wedges an AFI)."""
    if not pl_has_gp0():
        return  # nothing behind GP0: the write would hang the ARM, and no cart DMA can be running
    con.mw(0x43C00008, 0)
    time.sleep(PAUSE)


def set_afi(con: UBoot, hp2: bool = False) -> None:
    """HP0/HP1 (+ HP2 for a --blit bitstream) widths; only after the PL is loaded (the AFI registers hang the ARM otherwise)."""
    con.cmd(AFI_WIDTHS)
    if hp2:
        con.cmd(AFI_HP2_WIDTH)
