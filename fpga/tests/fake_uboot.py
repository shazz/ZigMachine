"""A fake U-Boot on a pty for tests/test_board_tools.py: a dict memory answering md.l / mw.l / crc32,
an hp-test engine model per HP port and a diag-firmware model. Nothing here touches the real board."""

from __future__ import annotations

import os
import select
import threading
import zlib


class FakeUBoot(threading.Thread):
    """U-Boot on the pty master. `ctrlc_needed`: Ctrl-Cs the autoboot loop eats before the prompt."""

    def __init__(self, ctrlc_needed: int = 0, silent: bool = False) -> None:
        super().__init__(daemon=True)
        self.master, slave = os.openpty()
        self.tty = os.ttyname(slave)
        self.mem: dict[int, int] = {}
        self.wedged: set[int] = set()
        self.ctrlc_needed, self.ctrlcs, self.silent = ctrlc_needed, 0, silent
        self.log: list[str] = []
        self.loaded: list[str] = []  # [bitstreams "programmed"]
        self.diag_broken = self.diag_bad = False
        self._slave = slave  # [kept open so the pty lives]
        self.start()

    def run(self) -> None:
        buf = b""
        while True:
            if not select.select([self.master], [], [], 0.05)[0]:
                continue
            try:
                data = os.read(self.master, 4096)
            except OSError:
                return
            for b in data:
                if b == 3:
                    self.ctrlcs += 1
                    if self.ctrlcs >= self.ctrlc_needed and not self.silent:
                        self.say("^C\r\nZynq> ")
                elif b == 13:
                    self.handle(buf.decode())
                    buf = b""
                else:
                    buf += bytes([b])

    def say(self, text: str) -> None:
        os.write(self.master, text.encode())

    def handle(self, line: str) -> None:
        self.log.append(line)
        out = line + "\r\n"
        for part in line.split(";"):
            out += self.exec(part.split())
        self.say(out + "Zynq> ")

    def exec(self, w: list[str]) -> str:
        if not w:
            return ""
        a = int(w[1], 16) if len(w) > 1 and w[0] != "dcache" else 0
        if w[0] == "mw.l":
            for i in range(int(w[3], 16) if len(w) > 3 else 1):
                self.mem[a + 4 * i] = int(w[2], 16)
            self.after_write(a, int(w[2], 16))
        elif w[0] == "md.l":
            n = int(w[2], 16)
            if a in (0x43C00010, 0x05FFFF14) and self.mem.get(0x43C00010) == 2:  # [a running cart advances]
                self.mem[0x43C00014] = self.mem.get(0x43C00014, 0) + 1
                self.mem[0x05FFFF14] = self.mem.get(0x05FFFF14, 0) + 1
            return "".join(
                f"{a + 4 * i:08x}: "
                + " ".join(f"{self.mem.get(a + 4 * j, 0):08x}" for j in range(i, min(i + 4, n)))
                + "    ....\r\n"
                for i in range(0, n, 4)
            )
        elif w[0] == "crc32":
            n = int(w[2], 16)
            data = b"".join(self.mem.get(a + i, 0).to_bytes(4, "little") for i in range(0, n, 4))[:n]
            return f"==> crc32 for {a:08x} ... {a + n - 1:08x} ==> {zlib.crc32(data):08x}\r\n"
        return ""

    def after_write(self, a: int, v: int) -> None:
        for port, base in ((0, 0x43C00100), (1, 0x43C00200)):
            if a == base:
                self.hp_run(port, base, v)
        if a == 0x43C00008 and v == 1 and self.mem.get(0x05FFFE04) in (3, 4):
            self.diag(self.mem[0x05FFFE04])
        elif a == 0x43C00008 and v == 1:
            self.mem[0x43C00010] = 2
            self.mem[0x43C00014] = self.mem.get(0x43C00014, 0) + 1

    def hp_run(self, port: int, base: int, ctrl: int) -> None:
        m, n = self.mem, (self.mem.get(base + 8, 0) + 1) * self.mem.get(base + 0x14, 0)
        if ctrl & 8:  # [the SoC's own bridge: COUNT beats whatever LEN says]
            n = m.get(base + 0x14, 0)
        if port in self.wedged and ctrl & 1:
            m[base + 0x20], m[base + 0x24] = 1, 0
            return
        m[base + 0x20], m[base + 0x24], m[base + 0x28] = 2, n, 0
        if ctrl & 2 and ctrl & 8 == 0:
            for i in range(n):
                m[m[base + 4] + 4 * i] = m[base + 0x1C] + 2 * i
        if ctrl & 4 and not ctrl & 0x20 and m.get(base + 0xC, 3) < 3:  # [narrow read without LANE: odd words land high]
            m[base + 0x28] = n // 2
        elif ctrl & 4:
            m[base + 0x28] = sum(m.get(m[base + 4] + 4 * i) != m[base + 0x1C] + 2 * i for i in range(n))

    def diag(self, mode: int) -> None:
        m = self.mem
        m[0x43C00010], m[0x43C00014] = (mode << 8 | 0x40, 0x5A0302) if self.diag_broken else (mode << 8 | 0x44, mode)
        if mode == 3:
            for i in range(8):
                m[0x05F01100 + 4 * i], m[0x05F80000 + 4 * i] = (
                    0x55667788,
                    0x002C3239 if not (self.diag_bad and i == 2) else 0,
                )
        else:
            for i in range(0x20):
                m[0x05F80000 + 4 * i] = (i + 1) * 0x010101
            for i, v in enumerate([0xFF040404, 0xFF030303, 0xFF020202, 0xFF010101] * 2):
                m[0x05F80C00 + 4 * i] = v
