"""The board's Linux root shell (ttyPS0 through the CH340, 921600) as a library, for board_fps.py.

Unlike uboot_serial.py (U-Boot's `Zynq>` prompt) a shell's prompt is not fixed, so every command
is followed by `echo @@ZM<n> $?@@` and its reply is everything up to that marker: a missing marker
is an error (BoardSilent), never a silent empty reply. The echoed command line holds `$?`, not a
number, so the marker cannot match the echo. Lines glass logs to the console between the command
and the marker come back in the output; callers pick their lines by prefix.
"""

from __future__ import annotations

import itertools
import os
import re
import time

BAUD = 921600
TTY = "/dev/ttyUSB0"


class BoardSilent(RuntimeError):
    """The shell did not finish a command in time: the board (or its console) stopped answering."""


class LinuxConsole:
    def __init__(self, tty: str | None = None, port: object | None = None) -> None:
        if port is None:
            import serial  # [lazy: the tests pass a fake port]

            port = serial.Serial(tty or os.environ.get("BOARD_TTY") or TTY, BAUD, timeout=0.05)
        self.port = port
        self._n = itertools.count(1)

    def _drain(self, quiet: float) -> str:
        out, end = b"", time.monotonic() + quiet
        while time.monotonic() < end:
            got = self.port.read(65536)
            if got:
                out += got
                end = time.monotonic() + quiet
        return out.decode(errors="replace")

    def login(self) -> None:
        """Wake the console; log in as root if it shows a login prompt."""
        self.port.write(b"\r")
        if "login:" in self._drain(1.0):
            self.port.write(b"root\r")
            self._drain(1.5)

    def run(self, cmd: str, timeout: float = 10.0) -> tuple[int, str]:
        """`cmd`'s exit status and output (its echo dropped)."""
        tag = f"@@ZM{next(self._n)}"
        marker = re.compile(re.escape(tag) + r" (\d+)@@")
        self.port.reset_input_buffer()
        self.port.write(f'{cmd}; echo "{tag} $?@@"\r'.encode())
        buf, end = "", time.monotonic() + timeout
        while time.monotonic() < end:
            buf += self.port.read(65536).decode(errors="replace")
            m = marker.search(buf)
            if m:
                lines = buf[: m.start()].replace("\r", "").split("\n")
                body = [ln for ln in lines if tag not in ln]  # the echoed command line
                return int(m.group(1)), "\n".join(body).strip("\n")
        raise BoardSilent(f"no reply to {cmd!r} within {timeout:g} s (got {buf[-120:]!r})")

    def revive(self) -> bool:
        """After a BoardSilent: Ctrl-C, Enter, and one trivial command. True if the shell answers."""
        self.port.write(b"\x03\r")
        self._drain(1.0)
        try:
            return self.run("true", timeout=5.0)[0] == 0
        except BoardSilent:
            return False
