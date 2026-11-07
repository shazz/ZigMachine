"""vicemon.py: drive a headless x64sc through its text remote monitor, deterministically.

Boots the PRG with `-initbreak <addr>` (VICE stops in the monitor the first time the PC gets
there), then each command is sent over TCP and answered up to the next prompt. Colodore
palette, no CRT filter, so screenshots hold exact .vpl colours.
"""
import atexit
import os
import re
import socket
import subprocess
import time

X64SC = os.path.expanduser("~/.local/c64/bin/x64sc")
PROMPT = re.compile(rb"\(C:\$[0-9a-f]{4}\) $")


class Vice:
    def __init__(self, prg: str, initbreak: int, port: int = int(os.environ.get('VICE_PORT', '6510')), extra: list[str] | None = None) -> None:
        args = [X64SC, "-console", "-default", "+sound", "-warp",
                "-VICIIfilter", "0", "-VICIIextpal", "-VICIIpalette", "colodore",
                "-VICIIborders", "0",
                # neutral colour pipeline: pixels are then exactly colodore.vpl's entries
                "-VICIIbrightness", "1000", "-VICIIcontrast", "1000", "-VICIIsaturation", "1000",
                "-VICIIgamma", "1000", "-VICIItint", "1000",
                "-initbreak", hex(initbreak),
                "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
                "-autostartprgmode", "1", "-autostart", os.path.abspath(prg)] + (extra or [])
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        atexit.register(self.proc.kill)  # never leave an emulator holding the port
        for _ in range(200):
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), timeout=120)
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError("monitor never came up")
        self.read()

    def read(self) -> str:
        buf = b""
        while not PROMPT.search(buf):
            chunk = self.sock.recv(65536)
            if not chunk:
                break
            buf += chunk
        return buf.decode("latin-1")

    def cmd(self, c: str) -> str:
        self.sock.sendall(c.encode() + b"\n")
        return self.read()

    def mem(self, a: int, b: int) -> bytes:
        """Bytes a..b inclusive, parsed from `m` output."""
        out = bytearray()
        for line in self.cmd(f"m {a:04x} {b:04x}").splitlines():
            m = re.match(r">C:([0-9a-f]{4})\s+((?:[0-9a-f]{2}\s+)+)", line)
            if m:
                out += bytes(int(x, 16) for x in m.group(2).split()[:16])
        return bytes(out[: b - a + 1])

    def close(self) -> None:
        try:
            self.sock.sendall(b"quit\n")
        except OSError:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
